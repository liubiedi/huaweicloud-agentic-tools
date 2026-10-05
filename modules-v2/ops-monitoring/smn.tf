# --- Notification topic ---

locals {
  topic_name = replace(var.topic_name, "{account-name}", var.account_name)
}

resource "huaweicloud_smn_topic" "lz_alerts" {
  name         = local.topic_name
  display_name = local.topic_name
  tags         = var.tags
}

resource "huaweicloud_smn_subscription" "this" {
  for_each = { for idx, s in var.subscribers : "${s.protocol}-${idx}" => s }

  topic_urn = huaweicloud_smn_topic.lz_alerts.id
  endpoint  = each.value.endpoint
  protocol  = each.value.protocol
  remark    = "Landing zone subscriber"
}

# --- Notification delivery policies ---
# Note: Ordered failover is configured only for sms and callnotify subscriptions.
resource "huaweicloud_smn_notify_policy" "this" {
  for_each = toset([for s in var.subscribers : s.protocol if contains(["sms", "callnotify"], s.protocol)])

  topic_urn = huaweicloud_smn_topic.lz_alerts.id
  protocol  = each.value

  polling {
    order             = 1
    subscription_urns = [for k, sub in huaweicloud_smn_subscription.this : sub.id if sub.protocol == each.value]
  }
}

resource "huaweicloud_smn_logtank" "this" {
  count = var.smn_lts_group_id != "" ? 1 : 0

  topic_urn     = huaweicloud_smn_topic.lz_alerts.id
  log_group_id  = var.smn_lts_group_id
  log_stream_id = var.smn_lts_stream_id
}
