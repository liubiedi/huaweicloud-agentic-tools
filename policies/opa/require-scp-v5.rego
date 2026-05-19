package terraform.lz.scp

import rego.v1

# All SCPs must use Version "5.0" syntax
deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "huaweicloud_organizations_policy"
  resource.change.actions[_] in ["create", "update"]

  content := json.unmarshal(resource.change.after.content)
  content.Version != "5.0"

  msg := sprintf(
    "POLICY VIOLATION: SCP '%s' uses Version '%s' instead of '5.0'. Huawei Cloud SCPs require v5.0 syntax.",
    [resource.name, content.Version],
  )
}

# Deny SCPs without any statements
deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "huaweicloud_organizations_policy"
  resource.change.actions[_] in ["create", "update"]

  content := json.unmarshal(resource.change.after.content)
  count(content.Statement) == 0

  msg := sprintf(
    "POLICY VIOLATION: SCP '%s' has no statements.",
    [resource.name],
  )
}
