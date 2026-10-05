# --- Provider requirements ---

terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = { source = "huaweicloud/huaweicloud", version = "~> 1.87" }
  }
}

# --- Workload security groups ---
# Note: Attach groups to ECS interfaces in the workload configuration.

locals {
  groups = { for g in var.security_groups : g.name => g }

  # Stable rule keys
  rules = {
    for r in var.sg_rules :
    "${r.sg}|${r.direction}|${coalesce(r.protocol, "any")}|${coalesce(r.ports, "all")}|${r.remote}" => r
  }
}

resource "huaweicloud_networking_secgroup" "this" {
  for_each = local.groups

  name        = each.value.name
  description = each.value.description
  # Explicit security rules
  delete_default_rules = true
  tags                 = each.value.tags
}

resource "huaweicloud_networking_secgroup_rule" "this" {
  for_each = local.rules

  security_group_id = huaweicloud_networking_secgroup.this[each.value.sg].id
  direction         = each.value.direction
  ethertype         = "IPv4"
  action            = each.value.action
  description       = each.value.description

  # All-protocol handling
  protocol = each.value.protocol == null || each.value.protocol == "any" ? null : each.value.protocol
  # Port selection
  # Note: Blank means all ports; ICMP omits ports.
  ports = (each.value.ports == null || each.value.ports == "" || each.value.protocol == "icmp") ? null : each.value.ports

  # Remote target resolution
  # Note: Group references must belong to the same account.
  remote_group_id = (
    startswith(each.value.remote, "sg:")
    ? huaweicloud_networking_secgroup.this[trimprefix(each.value.remote, "sg:")].id
    : each.value.remote == "self" ? huaweicloud_networking_secgroup.this[each.value.sg].id : null
  )
  remote_ip_prefix = (
    startswith(each.value.remote, "sg:") || each.value.remote == "self" ? null : each.value.remote
  )
}
