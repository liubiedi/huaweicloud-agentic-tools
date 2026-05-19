package terraform.lz.region

import rego.v1

allowed_regions := {
  "cn-east-3",
  "cn-north-4",
  "cn-south-1",
  "ap-southeast-1",
  "ap-southeast-2",
  "ap-southeast-3",
}

# Exempt resources that must use the CTS global endpoint
cts_exempt_types := {
  "huaweicloud_cts_tracker",
  "huaweicloud_cts_notification",
  "huaweicloud_cts_data_tracker",
}

deny contains msg if {
  resource := input.resource_changes[_]
  resource.change.actions[_] in ["create", "update"]
  not resource.type in cts_exempt_types

  region := resource.change.after.region
  region != null
  not region in allowed_regions

  msg := sprintf(
    "POLICY VIOLATION: Resource '%s' (type: %s) is being deployed to region '%s' which is outside the approved region allowlist: %v",
    [resource.name, resource.type, region, allowed_regions],
  )
}

# KMS keys must have rotation enabled
deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "huaweicloud_kms_key"
  resource.change.actions[_] in ["create", "update"]
  resource.change.after.rotation_enabled != true

  msg := sprintf(
    "POLICY VIOLATION: KMS key '%s' does not have rotation enabled.",
    [resource.name],
  )
}

# Security groups must not allow 0.0.0.0/0 on sensitive ports
deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "huaweicloud_networking_secgroup_rule"
  resource.change.actions[_] in ["create", "update"]

  resource.change.after.direction == "ingress"
  resource.change.after.remote_ip_prefix == "0.0.0.0/0"
  resource.change.after.port_range_min <= 22
  resource.change.after.port_range_max >= 22

  msg := sprintf(
    "POLICY VIOLATION: Security group rule '%s' allows SSH (port 22) from 0.0.0.0/0.",
    [resource.name],
  )
}
