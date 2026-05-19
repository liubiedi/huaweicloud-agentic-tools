output "tag_policy_id" {
  value       = huaweicloud_organizations_policy.required_tags.id
  description = "Organizations tag policy ID"
}

output "cost_rule_ids" {
  value = {
    untagged_resources = huaweicloud_rms_policy_assignment.untagged_resources.id
    unattached_eips    = huaweicloud_rms_policy_assignment.unattached_eips.id
    unattached_evs     = huaweicloud_rms_policy_assignment.unattached_evs.id
  }
  description = "Map of cost governance RMS rule name to assignment ID"
}
