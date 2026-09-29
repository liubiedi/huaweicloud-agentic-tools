# --- Cloud Eye alarms ---

resource "huaweicloud_ces_alarmrule" "custom" {
  for_each = { for r in var.custom_alarm_rules : r.name => r }

  alarm_name        = each.value.name
  alarm_description = lookup(each.value, "description", "")

  metric {
    namespace   = each.value.namespace
    metric_name = each.value.metric_name
    dimensions {
      name  = each.value.dimension_name
      value = each.value.dimension_value
    }
  }

  condition {
    period              = lookup(each.value, "period", 60)
    filter              = lookup(each.value, "filter", "average")
    comparison_operator = each.value.comparison_operator
    value               = each.value.threshold
    unit                = lookup(each.value, "unit", "")
    count               = lookup(each.value, "count", 1)
  }

  alarm_actions {
    type              = "notification"
    notification_list = [huaweicloud_smn_topic.lz_alerts.id]
  }

  alarm_enabled        = true
  alarm_action_enabled = true
}

# --- One-click alarm bundles ---

data "huaweicloud_ces_one_click_alarms" "available" {
  count = length(var.one_click_alarms) > 0 ? 1 : 0
}

locals {
  _oneclick_id_by_ns = length(var.one_click_alarms) > 0 ? {
    for o in data.huaweicloud_ces_one_click_alarms.available[0].one_click_alarms : o.namespace => o.one_click_alarm_id
  } : {}
}

resource "huaweicloud_ces_one_click_alarm" "this" {
  for_each = { for o in var.one_click_alarms : o.namespace => o }

  one_click_alarm_id = local._oneclick_id_by_ns[each.value.namespace]

  dimension_names {
    event = each.value.event_enabled
  }

  notification_enabled = true

  alarm_notifications {
    type              = "notification"
    notification_list = [huaweicloud_smn_topic.lz_alerts.id]
  }
  ok_notifications {
    type              = "notification"
    notification_list = [huaweicloud_smn_topic.lz_alerts.id]
  }
  notification_begin_time = "00:00"
  notification_end_time   = "23:59"

  # Note: Create topic subscriptions before enabling alarms.
  depends_on = [huaweicloud_smn_subscription.this]

  # Note: Ignore bundle ID drift because lookup results change after creation.
  lifecycle {
    ignore_changes = [one_click_alarm_id]
  }
}

