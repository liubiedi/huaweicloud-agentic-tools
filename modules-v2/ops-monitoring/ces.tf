# CES alarm scaffolding.
#
# Note: huaweicloud_ces_one_click_alarm takes a `one_click_alarm_id` (a UUID
# returned by Huawei's console after enabling a one-click bundle) and a
# `dimension_names` block. Namespace strings like SYS.ECS are not direct
# inputs. Day-1 ships this section as a custom-alarm placeholder; populate
# var.custom_alarm_rules with hand-built rules instead, or wire the
# one-click ID flow once known.

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

# ---- One-click monitoring ----
# Enable Huawei's predefined one-click alarm bundles. The bundle ID is resolved
# from the namespace via the ces_one_click_alarms data source (no console lookup
# needed). The bundle applies to all resources of the service (no per-metric
# dimensions); event_enabled toggles its event alarm rules. Each enabled bundle
# notifies the SMN topic.

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

  # Notify chain: one-click alarm -> SMN topic -> its subscriptions. Ensure the
  # topic subscriptions exist before the alarm is enabled so alerts have
  # recipients.
  depends_on = [huaweicloud_smn_subscription.this]

  # The ces_one_click_alarms data source returns the TEMPLATE id (e.g.
  # CBRSystemOneClickAlarm) before the bundle exists, but the created-INSTANCE id
  # (oca...) afterwards. Re-resolving it on every plan would force an immutable
  # update ("one_click_alarm_id can't be updated"). The id only matters at create,
  # so ignore drift on it after the bundle exists.
  lifecycle {
    ignore_changes = [one_click_alarm_id]
  }
}

# ---- Deferred (schema verification needed on first apply) ----
#
# huaweicloud_ces_notification_mask - requires resource_type + mask_type +
#                                     schema checking before first use
