# Firewall alarm notifications -> SMN topic (one config per alarm type).
# Types: 0 attack, 1 traffic threshold (severity 1 = 80%), 2 EIP unprotected,
# 3 threat intelligence. alarm_time_period 1 = all day.

locals {
  alarms = merge(
    var.enable_attack_alarm ? { attack = {
      type = 0, severity = "CRITICAL,HIGH", count = 1, time = 5
    } } : {},
    var.enable_traffic_alarm ? { traffic = {
      type = 1, severity = "1", count = 1, time = 1
    } } : {},
    var.enable_eip_unprotected_alarm ? { eip-unprotected = {
      type = 2, severity = "3", count = 1, time = 1
    } } : {},
    var.enable_threat_intel_alarm ? { threat-intel = {
      type = 3, severity = "CRITICAL,HIGH", count = 1, time = 5
    } } : {}
  )
}

# Resolve the alarm-topic NAME to a URN in the CFW account.
data "huaweicloud_smn_topics" "alarm" {
  count = length(local.alarms) > 0 ? 1 : 0

  name = var.alarm_topic_name

  lifecycle {
    postcondition {
      condition     = length(self.topics) > 0
      error_message = "SMN topic '${var.alarm_topic_name}' not found in the CFW account. 06-observability creates the ops topics - apply 06 first, or fix alarm_topic_name."
    }
  }
}

resource "huaweicloud_cfw_alarm_config" "this" {
  for_each = local.alarms

  fw_instance_id    = var.fw_instance_id
  alarm_type        = each.value.type
  alarm_time_period = 1
  frequency_count   = each.value.count
  frequency_time    = each.value.time
  severity          = each.value.severity
  topic_urn         = data.huaweicloud_smn_topics.alarm[0].topics[0].topic_urn
}
