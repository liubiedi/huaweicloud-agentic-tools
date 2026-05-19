output "ops_smn_topic_urn" {
  value = module.ops_monitoring.smn_topic_urn
}

output "aom_prometheus_id" {
  value = module.ops_monitoring.aom_prometheus_id
}

output "tag_policy_id" {
  value = module.finance_governance.tag_policy_id
}

output "cost_rule_ids" {
  value = module.finance_governance.cost_rule_ids
}
