output "scp_policy_ids" {
  description = "IDs of the SCP documents created (general + tag, enforced + staged)."
  value = concat(
    [for p in huaweicloud_organizations_policy.enforced : p.id],
    [for p in huaweicloud_organizations_policy.staged : p.id],
    [for p in huaweicloud_organizations_policy.tag_enforced : p.id],
    [for p in huaweicloud_organizations_policy.tag_staged : p.id],
  )
}

output "enforced_guardrails" {
  description = "Guardrail keys that are LIVE (packed into the attached document(s))."
  value       = sort([for k, v in local.scp_all : k if v.enforce])
}

output "staged_guardrails" {
  description = "Guardrail keys created but NOT attached (inert)."
  value       = sort([for k, v in local.scp_all : k if !v.enforce])
}

output "predefined_tag_keys" {
  description = "Tag keys written to the per-account TMS predefined-tag dictionary."
  value       = [for t in var.predefined_tags : t.key]
}

output "config_recorder_id" {
  description = "Resource recorder (Config tracker) ID, or null when not created."
  value       = one(huaweicloud_rms_resource_recorder.this[*].id)
}

output "config_aggregator_urn" {
  description = "ORGANIZATION resource-aggregator URN, or null when not created."
  value       = one(huaweicloud_rms_resource_aggregator.org[*].urn)
}

output "conformance_pack_template_keys" {
  description = "Resolved template_key per deployed org conformance pack."
  value       = { for k, v in local.conformance_resolved : k => v.template_key }
}
