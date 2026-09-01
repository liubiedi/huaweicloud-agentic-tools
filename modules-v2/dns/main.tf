# ---- DNS zones (public + private) ----

resource "huaweicloud_dns_zone" "public" {
  for_each = { for z in var.public_zones : z.name => z }

  name                  = each.value.name
  zone_type             = "public"
  email                 = each.value.email != "" ? each.value.email : null
  ttl                   = each.value.ttl
  description           = each.value.description
  enterprise_project_id = var.enterprise_project_id
}

resource "huaweicloud_dns_zone" "private" {
  for_each = { for z in var.private_zones : z.name => z }

  name                  = each.value.name
  zone_type             = "private"
  ttl                   = each.value.ttl
  description           = each.value.description
  enterprise_project_id = var.enterprise_project_id
  proxy_pattern         = each.value.recursive ? "RECURSIVE" : "AUTHORITY"

  # The first VPC is the zone's primary router; the rest are attached below via
  # huaweicloud_dns_private_zone_associate (a private zone needs >=1 router).
  dynamic "router" {
    for_each = length(each.value.vpcs) > 0 ? [each.value.vpcs[0]] : []
    content {
      router_id = var.vpc_ids[router.value]
    }
  }
}

# Additional VPC associations (every VPC after the first in each private zone).
locals {
  private_zone_extra_assoc = merge([
    for z in var.private_zones : {
      for vpc in slice(z.vpcs, 1, length(z.vpcs)) :
      "${z.name}__${vpc}" => { zone = z.name, vpc = vpc }
    } if length(z.vpcs) > 1
  ]...)

  zone_id_by_name = merge(
    { for k, v in huaweicloud_dns_zone.public : k => v.id },
    { for k, v in huaweicloud_dns_zone.private : k => v.id },
  )
}

resource "huaweicloud_dns_private_zone_associate" "this" {
  for_each = local.private_zone_extra_assoc

  zone_id   = huaweicloud_dns_zone.private[each.value.zone].id
  router_id = var.vpc_ids[each.value.vpc]
}

# ---- Record sets ----

resource "huaweicloud_dns_recordset" "this" {
  for_each = { for r in var.recordsets : "${r.zone}__${r.name}__${r.type}" => r }

  zone_id     = local.zone_id_by_name[each.value.zone]
  name        = each.value.name
  type        = each.value.type
  records     = each.value.records
  ttl         = each.value.ttl
  description = each.value.description
}

# ---- Resolver endpoints (inbound + outbound) ----

locals {
  # One ip_addresses block per resolver IP (Huawei requires >=2). Blocks = the larger
  # of subnets vs ips: with more IPs than subnets the extra IPs reuse subnets by
  # cycling (so "2 IPs in 1 subnet" works, per the provider's own examples); with no
  # fixed IPs, one block per subnet (IP auto-assigned).
  endpoint_ips = {
    for e in var.resolver_endpoints : e.name => [
      for idx in range(max(length(e.subnets), length(e.ips))) : {
        subnet_id = var.subnet_ids["${e.vpc}__${e.subnets[idx % length(e.subnets)]}"]
        ip        = idx < length(e.ips) ? e.ips[idx] : null
      }
    ]
  }
}

resource "huaweicloud_dns_endpoint" "this" {
  for_each = { for e in var.resolver_endpoints : e.name => e }

  name      = each.value.name
  direction = each.value.direction

  dynamic "ip_addresses" {
    for_each = local.endpoint_ips[each.key]
    content {
      subnet_id = ip_addresses.value.subnet_id
      ip        = ip_addresses.value.ip
    }
  }
}

# ---- Outbound forwarding rules + VPC associations ----

resource "huaweicloud_dns_resolver_rule" "this" {
  for_each = { for r in var.resolver_rules : r.name => r }

  name        = each.value.name
  endpoint_id = huaweicloud_dns_endpoint.this[each.value.endpoint].id
  domain_name = each.value.domain_name

  dynamic "ip_addresses" {
    for_each = each.value.target_ips
    content {
      ip = ip_addresses.value
    }
  }
}

locals {
  rule_assoc = merge([
    for r in var.resolver_rules : {
      for vpc in r.vpcs : "${r.name}__${vpc}" => { rule = r.name, vpc = vpc }
    }
  ]...)
}

resource "huaweicloud_dns_resolver_rule_associate" "this" {
  for_each = local.rule_assoc

  resolver_rule_id = huaweicloud_dns_resolver_rule.this[each.value.rule].id
  vpc_id           = var.vpc_ids[each.value.vpc]
}

# ---- DNS query access logging (to LTS) ----
# A resolver access log needs an existing LTS group + stream. By default the
# module creates them. With manage_query_log_infra = false it looks them up by
# name instead - used when the observability environment owns the log infra,
# so a fresh sequential deploy works strictly in numeric order.

locals {
  lts_group_names = distinct([for a in var.access_logs : a.lts_group])
  lts_streams     = { for a in var.access_logs : "${a.lts_group}__${a.lts_stream}" => a }
}

resource "huaweicloud_lts_group" "dns" {
  for_each = var.manage_query_log_infra ? toset(local.lts_group_names) : toset([])

  group_name            = each.value
  ttl_in_days           = var.access_log_lts_ttl_days
  enterprise_project_id = var.enterprise_project_id
}

resource "huaweicloud_lts_stream" "dns" {
  for_each = var.manage_query_log_infra ? local.lts_streams : {}

  group_id              = huaweicloud_lts_group.dns[each.value.lts_group].id
  stream_name           = each.value.lts_stream
  enterprise_project_id = var.enterprise_project_id
}

# External infra mode: resolve the same names to IDs.
data "huaweicloud_lts_groups" "dns" {
  count = !var.manage_query_log_infra && length(var.access_logs) > 0 ? 1 : 0
}

data "huaweicloud_lts_streams" "dns" {
  for_each = var.manage_query_log_infra ? {} : local.lts_streams

  log_group_name = each.value.lts_group
  name           = each.value.lts_stream

  lifecycle {
    postcondition {
      condition     = length(self.streams) > 0
      error_message = "DNS query-log LTS stream '${each.value.lts_stream}' (group '${each.value.lts_group}') not found in this account. 06-observability owns the query-log infrastructure - apply 06 first (see deps.json)."
    }
  }
}

locals {
  _ext_groups = { for g in try(data.huaweicloud_lts_groups.dns[0].groups, []) : g.name => g.id }
  qlog_group_ids = var.manage_query_log_infra ? (
    { for k, v in huaweicloud_lts_group.dns : k => v.id }) : (
  { for n in local.lts_group_names : n => local._ext_groups[n] })
  qlog_stream_ids = var.manage_query_log_infra ? (
    { for k, v in huaweicloud_lts_stream.dns : k => v.id }) : (
  { for k, v in data.huaweicloud_lts_streams.dns : k => v.streams[0].id })
}

resource "huaweicloud_dns_resolver_access_log" "this" {
  for_each = { for a in var.access_logs : a.name => a }

  lts_group_id = local.qlog_group_ids[each.value.lts_group]
  lts_topic_id = local.qlog_stream_ids["${each.value.lts_group}__${each.value.lts_stream}"]
  vpc_ids      = [for v in each.value.vpcs : var.vpc_ids[v]]

  lifecycle {
    precondition {
      condition     = var.manage_query_log_infra || contains(keys(local._ext_groups), each.value.lts_group)
      error_message = "DNS query-log LTS group '${each.value.lts_group}' not found in this account. 06-observability owns it - apply 06 first (see deps.json)."
    }
  }
}
