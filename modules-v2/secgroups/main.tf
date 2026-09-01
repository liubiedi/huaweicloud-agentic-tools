# Workload security groups. Called once per member account; groups and rules
# are fully declarative inputs. Security groups are region-scoped (no VPC
# binding); attachment to ECS network interfaces is a workload-team step.

locals {
  groups = { for g in var.security_groups : g.name => g }

  # Stable per-rule key: content-addressed so adding/removing one row never
  # touches sibling rules. Rule fields are ForceNew upstream anyway.
  rules = {
    for r in var.sg_rules :
    "${r.sg}|${r.direction}|${coalesce(r.protocol, "any")}|${coalesce(r.ports, "all")}|${r.remote}" => r
  }
}

resource "huaweicloud_networking_secgroup" "this" {
  for_each = local.groups

  name        = each.value.name
  description = each.value.description
  # No implicit allow-alls: every rule is a visible workbook row.
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

  # protocol "any" (or blank) = all protocols: the attribute must be omitted.
  protocol = each.value.protocol == null || each.value.protocol == "any" ? null : each.value.protocol
  # ports blank = all ports of the protocol; icmp never carries ports.
  ports = (each.value.ports == null || each.value.ports == "" || each.value.protocol == "icmp") ? null : each.value.ports

  # remote: "sg:<name>" = another group IN THIS ACCOUNT (SG references cannot
  # cross accounts), "self" = the rule's own group, else a CIDR.
  remote_group_id = (
    startswith(each.value.remote, "sg:")
    ? huaweicloud_networking_secgroup.this[trimprefix(each.value.remote, "sg:")].id
    : each.value.remote == "self" ? huaweicloud_networking_secgroup.this[each.value.sg].id : null
  )
  remote_ip_prefix = (
    startswith(each.value.remote, "sg:") || each.value.remote == "self" ? null : each.value.remote
  )
}
