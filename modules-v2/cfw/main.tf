locals {
  # ---- friendly-string -> API-int enum maps ----
  addr_type_num = { ipv4 = 0, ipv6 = 1, domain = 2 } # black/white list allows 'domain'
  dom_type_num  = { application = 0, network = 1 }
  proto_num     = { tcp = 6, udp = 17, icmp = 1, icmpv6 = 58, any = -1 }
  action_num    = { allow = 0, deny = 1 }
  status_num    = { enable = 1, disable = 0 }
  list_type_num = { blacklist = 4, whitelist = 5 }
  direction_num = { source = 0, destination = 1 }
  # ACL rule direction (internet border only): 0=inbound, 1=outbound.
  rule_direction_num = { inbound = 0, outbound = 1 }
  # ACL rule kind -> (border, rule type). type: 0=Internet, 1=VPC, 2=NAT.
  acl_kind = {
    eip = { border = "internet", type = 0 }
    nat = { border = "internet", type = 2 }
    vpc = { border = "vpc", type = 1 }
  }
  # ACL destination_domain_group_type: 4=application, 6=network (differs from the
  # domain-name-group resource's own type, 0/1).
  dom_group_rule_type = { application = 4, network = 6 }

  # Pick the protected object for a border.
  object_for = { internet = var.internet_object_id, vpc = var.vpc_object_id }

  # Domain-group type by name (for destination_domain_group_type on ACL rules).
  domain_group_type_by_name = { for g in var.domain_groups : g.name => g.type }

  # Protocols covered by each service group (for custom_service_groups.protocols).
  svc_group_protocols = {
    for g in var.service_groups : g.name =>
    distinct([for m in g.members : local.proto_num[split("/", m)[0]]])
  }
}

# ---- IP address groups (+ members) ----

resource "huaweicloud_cfw_address_group" "this" {
  for_each = { for g in var.address_groups : g.name => g }

  object_id    = local.object_for[each.value.border]
  name         = each.value.name
  address_type = local.addr_type_num[each.value.address_type]
  description  = each.value.description

  # Replace before destroy: ACL rules may still reference the group.
  lifecycle {
    create_before_destroy = true
  }
}

locals {
  address_members = merge([
    for g in var.address_groups : {
      for a in g.members : "${g.name}__${a}" => { group = g.name, address = a, atype = g.address_type }
    }
  ]...)
}

resource "huaweicloud_cfw_address_group_member" "this" {
  for_each = local.address_members

  group_id     = huaweicloud_cfw_address_group.this[each.value.group].id
  address      = each.value.address
  address_type = local.addr_type_num[each.value.atype]

  lifecycle {
    create_before_destroy = true
  }
}

# ---- Domain name groups ----

resource "huaweicloud_cfw_domain_name_group" "this" {
  for_each = { for g in var.domain_groups : g.name => g }

  fw_instance_id = var.fw_instance_id
  object_id      = local.object_for[each.value.border]
  name           = each.value.name
  type           = local.dom_type_num[each.value.type]
  description    = each.value.description

  dynamic "domain_names" {
    for_each = each.value.domains
    content {
      domain_name = domain_names.value
    }
  }

  # Replace before destroy: ACL rules may still reference the group.
  lifecycle {
    create_before_destroy = true
  }
}

# ---- Service groups (+ members) ----

resource "huaweicloud_cfw_service_group" "this" {
  for_each = { for g in var.service_groups : g.name => g }

  object_id   = local.object_for[each.value.border]
  name        = each.value.name
  description = each.value.description

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  # member string 'protocol/srcport/dstport' ('any' port -> full range).
  service_members = merge([
    for g in var.service_groups : {
      for m in g.members : "${g.name}__${m}" => {
        group    = g.name
        protocol = local.proto_num[split("/", m)[0]]
        src_port = split("/", m)[1] == "any" ? "1-65535" : split("/", m)[1]
        dst_port = split("/", m)[2] == "any" ? "1-65535" : split("/", m)[2]
      }
    }
  ]...)
}

resource "huaweicloud_cfw_service_group_member" "this" {
  for_each = local.service_members

  group_id    = huaweicloud_cfw_service_group.this[each.value.group].id
  protocol    = each.value.protocol
  source_port = each.value.src_port
  dest_port   = each.value.dst_port

  lifecycle {
    create_before_destroy = true
  }
}

# ---- ACL rules ----

locals {
  acl_parsed = {
    for r in var.acl_rules : r.name => {
      border = local.acl_kind[r.kind].border
      type   = local.acl_kind[r.kind].type
      action = local.action_num[r.action]
      status = local.status_num[r.status]
      desc   = r.description
      # Internet-border rules need a direction (0=inbound, 1=outbound);
      # default: nat -> outbound, eip -> inbound. VPC rules have none.
      direction = local.acl_kind[r.kind].border != "internet" ? null : (
        r.direction != "" ? local.rule_direction_num[r.direction] :
        (r.kind == "nat" ? 1 : 0)
      )

      src_any       = contains(r.source, "any")
      src_addresses = [for t in r.source : t if !startswith(t, "addrgroup:") && t != "any"]
      src_groups    = [for t in r.source : trimprefix(t, "addrgroup:") if startswith(t, "addrgroup:")]

      dst_any       = contains(r.destination, "any")
      dst_addresses = [for t in r.destination : t if !startswith(t, "addrgroup:") && !startswith(t, "domaingroup:") && t != "any"]
      dst_groups    = [for t in r.destination : trimprefix(t, "addrgroup:") if startswith(t, "addrgroup:")]
      dst_domain    = [for t in r.destination : trimprefix(t, "domaingroup:") if startswith(t, "domaingroup:")]

      # 'any' service overrides everything -> applications=["ANY"].
      service_any     = contains(r.service, "any")
      applications    = contains(r.service, "any") ? ["ANY"] : [for t in r.service : trimprefix(t, "app:") if startswith(t, "app:")]
      svc_group_names = contains(r.service, "any") ? [] : [for t in r.service : trimprefix(t, "svcgroup:") if startswith(t, "svcgroup:")]
      inline_services = contains(r.service, "any") ? [] : [for t in r.service : t if !startswith(t, "app:") && !startswith(t, "svcgroup:")]
    }
  }
}

locals {
  # Catch-all rules (deny + source/destination/service all 'any') are split out
  # and created AFTER every other rule: bottom-pinned rules land in creation
  # order, and a deny-all that races above an allow would shadow it.
  acl_catchall = { for k, v in local.acl_parsed : k => v if v.action == 1 && v.src_any && v.dst_any && v.service_any }
  acl_regular  = { for k, v in local.acl_parsed : k => v if !(v.action == 1 && v.src_any && v.dst_any && v.service_any) }
}

resource "huaweicloud_cfw_acl_rule" "this" {
  for_each = local.acl_regular

  object_id           = local.object_for[each.value.border]
  name                = each.key
  type                = each.value.type
  action_type         = each.value.action
  address_type        = 0
  status              = each.value.status
  long_connect_enable = 0
  direction           = each.value.direction
  description         = each.value.desc

  source_addresses      = each.value.src_any ? ["0.0.0.0/0"] : (length(each.value.src_addresses) > 0 ? each.value.src_addresses : null)
  source_address_groups = length(each.value.src_groups) > 0 ? [for n in each.value.src_groups : huaweicloud_cfw_address_group.this[n].id] : null

  destination_addresses      = each.value.dst_any ? ["0.0.0.0/0"] : (length(each.value.dst_addresses) > 0 ? each.value.dst_addresses : null)
  destination_address_groups = length(each.value.dst_groups) > 0 ? [for n in each.value.dst_groups : huaweicloud_cfw_address_group.this[n].id] : null

  destination_domain_group_id   = length(each.value.dst_domain) > 0 ? huaweicloud_cfw_domain_name_group.this[each.value.dst_domain[0]].id : null
  destination_domain_group_name = length(each.value.dst_domain) > 0 ? each.value.dst_domain[0] : null
  destination_domain_group_type = length(each.value.dst_domain) > 0 ? local.dom_group_rule_type[local.domain_group_type_by_name[each.value.dst_domain[0]]] : null

  applications = length(each.value.applications) > 0 ? each.value.applications : null

  dynamic "custom_services" {
    for_each = each.value.inline_services
    content {
      # icmp is portless: the API stores no ports and the provider schema
      # still requires the attributes, so send "" (what a refresh writes to
      # state for an absent value) - a port range here drifts on every refresh
      protocol    = local.proto_num[split("/", custom_services.value)[0]]
      source_port = split("/", custom_services.value)[0] == "icmp" ? "" : (split("/", custom_services.value)[1] == "any" ? "1-65535" : split("/", custom_services.value)[1])
      dest_port   = split("/", custom_services.value)[0] == "icmp" ? "" : (split("/", custom_services.value)[2] == "any" ? "1-65535" : split("/", custom_services.value)[2])
    }
  }

  dynamic "custom_service_groups" {
    for_each = length(each.value.svc_group_names) > 0 ? [each.value.svc_group_names] : []
    content {
      protocols = distinct(flatten([for n in custom_service_groups.value : local.svc_group_protocols[n]]))
      group_ids = [for n in custom_service_groups.value : huaweicloud_cfw_service_group.this[n].id]
    }
  }

  # Pin to bottom; rules land in creation order (reorder in the console if
  # precedence matters).
  sequence {
    top    = 0
    bottom = 1
  }
}

# Tracks the SET of regular-rule ids: changes on create/replace (a rule can
# land below the catch-alls then), stays put on in-place updates.
resource "terraform_data" "rule_ids" {
  input = sort([for r in huaweicloud_cfw_acl_rule.this : r.id])
}

# Catch-all denies: same bottom pin, but depends_on guarantees they are created
# after every regular rule and therefore sit at the very bottom of the list.
resource "huaweicloud_cfw_acl_rule" "catchall" {
  for_each = local.acl_catchall

  object_id           = local.object_for[each.value.border]
  name                = each.key
  type                = each.value.type
  action_type         = each.value.action
  address_type        = 0
  status              = each.value.status
  long_connect_enable = 0
  direction           = each.value.direction
  description         = each.value.desc

  source_addresses      = ["0.0.0.0/0"]
  destination_addresses = ["0.0.0.0/0"]
  applications          = ["ANY"]

  sequence {
    top    = 0
    bottom = 1
  }

  depends_on = [huaweicloud_cfw_acl_rule.this]

  # Re-anchor the denies to the bottom whenever a rule is created or
  # replaced; in-place updates do not churn them.
  lifecycle {
    replace_triggered_by = [terraform_data.rule_ids]
  }
}

# ---- Black / white lists ----

resource "huaweicloud_cfw_black_white_list" "this" {
  for_each = { for i, b in var.black_white_lists : "${b.list_type}-${i}-${b.address}" => b }

  object_id    = local.object_for[each.value.border]
  list_type    = local.list_type_num[each.value.list_type]
  direction    = local.direction_num[each.value.direction]
  protocol     = local.proto_num[each.value.protocol]
  address_type = local.addr_type_num[each.value.address_type]
  address      = each.value.address
  port         = each.value.port != "" ? each.value.port : null
  description  = each.value.description
}
