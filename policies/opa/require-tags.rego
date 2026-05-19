package terraform.lz.tags

import rego.v1

required_tags := {"Environment", "CostCenter", "Owner", "Project"}

# Resources that are exempt from tagging requirements
tag_exempt_resource_types := {
  "huaweicloud_organizations_policy",
  "huaweicloud_organizations_policy_attach",
  "huaweicloud_organizations_trusted_service",
  "huaweicloud_identity_group_role_assignment",
  "huaweicloud_smn_subscription",
  "huaweicloud_dns_recordset",
}

deny contains msg if {
  resource := input.resource_changes[_]
  resource.change.actions[_] in ["create", "update"]
  not resource.type in tag_exempt_resource_types

  # Only flag resources that have a tags attribute
  _ = resource.change.after.tags

  missing := required_tags - {tag | resource.change.after.tags[tag]}
  count(missing) > 0

  msg := sprintf(
    "POLICY VIOLATION: Resource '%s' (type: %s) is missing required tags: %v",
    [resource.name, resource.type, missing],
  )
}
