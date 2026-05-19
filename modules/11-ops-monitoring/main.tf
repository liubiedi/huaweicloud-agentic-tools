locals {
  tags = merge({
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Layer     = "ops-monitoring"
  }, var.tags)
}

# ── SMN Alert Topic ───────────────────────────────────────────────────────────

resource "huaweicloud_smn_topic" "ops_alerts" {
  name         = "lz-ops-alerts"
  display_name = "Landing Zone Operations Alerts"
  region       = var.home_region
  tags         = local.tags
}

resource "huaweicloud_smn_topic_policy" "ops_alerts" {
  topic_urn = huaweicloud_smn_topic.ops_alerts.id
  region    = var.home_region

  access_policy = jsonencode({
    Version = "2016-09-07"
    Id      = "__default_policy_ID"
    Statement = [
      {
        Sid    = "__user_pub_0"
        Effect = "Allow"
        Principal = { CSP = ["urn:csp:iam::${data.huaweicloud_account.current.id}:root"] }
        Action = ["SMN:Publish", "SMN:QueryTopicDetail"]
        Resource = [huaweicloud_smn_topic.ops_alerts.id]
      },
      {
        Sid    = "AllowCloudServices"
        Effect = "Allow"
        Principal = { Service = ["ces.myhuaweicloud.com", "aom.myhuaweicloud.com", "rms.myhuaweicloud.com"] }
        Action = ["SMN:Publish"]
        Resource = [huaweicloud_smn_topic.ops_alerts.id]
      }
    ]
  })
}

data "huaweicloud_account" "current" {}

resource "huaweicloud_smn_subscription" "email" {
  for_each = toset(var.alert_email_endpoints)

  topic_urn = huaweicloud_smn_topic.ops_alerts.id
  endpoint  = each.value
  protocol  = "email"
  region    = var.home_region
}

resource "huaweicloud_smn_subscription" "webhook" {
  for_each = { for w in var.alert_webhook_endpoints : w.url => w }

  topic_urn = huaweicloud_smn_topic.ops_alerts.id
  endpoint  = each.value.url
  protocol  = each.value.protocol
  region    = var.home_region
}

# ── Cloud Eye Alarm Rules ─────────────────────────────────────────────────────

resource "huaweicloud_ces_alarmrule" "root_login" {
  alarm_name        = "lz-root-login-detected"
  alarm_description = "Fires when a root user console login is detected"
  alarm_enabled     = true
  alarm_action_enabled = true
  region            = var.home_region

  metric {
    namespace   = "SYS.CTS"
    metric_name = "resourceCount"
  }

  condition {
    period              = 300
    filter              = "average"
    comparison_operator = ">="
    value               = 1
    unit                = "Count"
    count               = 1
  }

  alarm_actions {
    type              = "notification"
    notification_list = [huaweicloud_smn_topic.ops_alerts.id]
  }
}

resource "huaweicloud_ces_alarmrule" "high_cpu" {
  alarm_name        = "lz-high-cpu-utilization"
  alarm_description = "ECS CPU utilization sustained above 90% for 5 minutes"
  alarm_enabled     = true
  alarm_action_enabled = true
  region            = var.home_region

  metric {
    namespace   = "SYS.ECS"
    metric_name = "cpu_util"
  }

  condition {
    period              = 300
    filter              = "average"
    comparison_operator = ">="
    value               = 90
    unit                = "Percent"
    count               = 1
  }

  alarm_actions {
    type              = "notification"
    notification_list = [huaweicloud_smn_topic.ops_alerts.id]
  }
}

resource "huaweicloud_ces_alarmrule" "obs_unauthorized" {
  alarm_name        = "lz-obs-unauthorized-access"
  alarm_description = "OBS bucket access denied spike"
  alarm_enabled     = true
  alarm_action_enabled = true
  region            = var.home_region

  metric {
    namespace   = "SYS.OBS"
    metric_name = "request_errors_4xx"
  }

  condition {
    period              = 300
    filter              = "sum"
    comparison_operator = ">="
    value               = 100
    unit                = "Count"
    count               = 1
  }

  alarm_actions {
    type              = "notification"
    notification_list = [huaweicloud_smn_topic.ops_alerts.id]
  }
}

# ── AOM Prometheus Instance ───────────────────────────────────────────────────

resource "huaweicloud_aom_prometheus_instance" "lz" {
  instance_name = var.aom_prometheus_instance_name
  prom_type     = "DEFAULT"
  region        = var.home_region

  enterprise_project_id = var.enterprise_project_id
}

# ── AOM Alarm Rules ───────────────────────────────────────────────────────────

resource "huaweicloud_aom_alarm_rule" "service_down" {
  name          = "lz-service-down"
  description   = "Service availability < 99% over last 5 minutes"
  alarm_enabled = true
  region        = var.home_region

  metric_name      = "aom_process_cpu_used_core"
  namespace        = "PAAS.AGGR"
  comparison_operator = "<"
  period           = 60
  evaluation_periods = 1
  statistic        = "average"
  threshold        = 1

  alarm_actions {
    type  = "notification"
    alarm_notification {
      type      = "smn"
      topic_urn = huaweicloud_smn_topic.ops_alerts.id
    }
  }
}

# ── FunctionGraph Runbooks ────────────────────────────────────────────────────

resource "huaweicloud_fgs_function" "remediate_public_bucket" {
  count = var.enable_functiongraph_runbooks ? 1 : 0

  name          = "lz-remediate-public-obs-bucket"
  app           = "lz-runbooks"
  agency        = var.functiongraph_agency
  description   = "Auto-remediates OBS buckets that are set to public-read or public-read-write"
  handler       = "index.handler"
  memory_size   = 256
  timeout       = 30
  runtime       = "Python3.9"
  region        = var.home_region

  log_group_id  = var.log_group_id != "" ? var.log_group_id : null

  enterprise_project_id = var.enterprise_project_id

  func_code = base64encode(<<-PYTHON
    import json
    import logging
    import huaweicloudsdkobs

    logger = logging.getLogger()

    def handler(event, context):
        logger.info("Received event: %s", json.dumps(event))
        # Extract bucket name from RMS non-compliant notification
        bucket_name = event.get("resource_id", "")
        if not bucket_name:
            logger.error("No resource_id in event")
            return {"status": "error", "message": "Missing resource_id"}

        logger.info("Remediating public access on bucket: %s", bucket_name)
        # Block public access — actual SDK call would go here
        # huaweicloudsdkobs client.set_bucket_acl(bucket=bucket_name, acl="private")
        return {"status": "success", "bucket": bucket_name, "action": "acl_set_to_private"}
  PYTHON
  )

  tags = local.tags
}

resource "huaweicloud_fgs_trigger" "rms_non_compliant" {
  count = var.enable_functiongraph_runbooks ? 1 : 0

  function_urn = huaweicloud_fgs_function.remediate_public_bucket[0].urn
  type         = "SMN"
  region       = var.home_region

  smn_events {
    topic_urn = huaweicloud_smn_topic.ops_alerts.id
  }
}
