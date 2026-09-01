output "smn_topic_urn" {
  description = "SMN topic URN - consumed by module 6 alarms + CES one-click in this module"
  value       = huaweicloud_smn_topic.lz_alerts.id
}

output "smn_topic_name" {
  description = "SMN topic name"
  value       = huaweicloud_smn_topic.lz_alerts.name
}

output "custom_alarm_rule_ids" {
  description = "Map of custom alarm rule name -> ID"
  value       = { for k, v in huaweicloud_ces_alarmrule.custom : k => v.id }
}
