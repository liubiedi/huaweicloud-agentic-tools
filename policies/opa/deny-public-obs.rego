package terraform.lz.obs

import rego.v1

# Deny any OBS bucket that exposes public ACLs or bucket policies
deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "huaweicloud_obs_bucket"
  resource.change.actions[_] in ["create", "update"]

  acl := resource.change.after.acl
  acl in ["public-read", "public-read-write"]

  msg := sprintf(
    "POLICY VIOLATION: OBS bucket '%s' has ACL '%s'. Only 'private' is allowed.",
    [resource.name, acl],
  )
}

deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "huaweicloud_obs_bucket"
  resource.change.actions[_] in ["create", "update"]

  not resource.change.after.versioning[_].status == "Enabled"

  msg := sprintf(
    "POLICY VIOLATION: OBS bucket '%s' does not have versioning enabled.",
    [resource.name],
  )
}

deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "huaweicloud_obs_bucket"
  resource.change.actions[_] in ["create", "update"]

  count(resource.change.after.encryption) == 0

  msg := sprintf(
    "POLICY VIOLATION: OBS bucket '%s' is not KMS-encrypted.",
    [resource.name],
  )
}
