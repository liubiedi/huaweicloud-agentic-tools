# ---- S2C VPN gateways ----
# attachment=vpc binds to a 05-network VPC (vpc_id + connect_subnet + local_subnets);
# attachment=er binds to the hub ER. network_type=public creates two EIPs inline.

locals {
  # Distinct flavor+attachment combos across all gateways. Blank flavor -> the API
  # default (Professional1). We query VPN AZ availability once per combo.
  gw_az_combos = toset([
    for g in var.gateways : "${g.flavor != "" ? g.flavor : "Professional1"}__${g.attachment}"
  ])

  # Per-gateway AZ list: the configured AZs if given, otherwise the first
  # two AZs the API reports as valid for that flavor+attachment.
  gw_azs = {
    for g in var.gateways : g.name => (
      length(g.azs) > 0 ? g.azs : slice(
        data.huaweicloud_vpn_gateway_availability_zones.this["${g.flavor != "" ? g.flavor : "Professional1"}__${g.attachment}"].names,
        0, 2
      )
    )
  }
}

# Valid AZs per flavor+attachment. attachment_type must match the gateway's, since
# vpc and er gateways can be offered in different AZs.
data "huaweicloud_vpn_gateway_availability_zones" "this" {
  for_each = local.gw_az_combos

  flavor          = split("__", each.key)[0]
  attachment_type = split("__", each.key)[1]
}

resource "huaweicloud_vpn_gateway" "this" {
  for_each = { for g in var.gateways : g.name => g }

  name                  = each.value.name
  availability_zones    = local.gw_azs[each.value.name]
  attachment_type       = each.value.attachment
  network_type          = each.value.network_type
  ha_mode               = each.value.ha_mode
  asn                   = each.value.asn
  flavor                = each.value.flavor != "" ? each.value.flavor : null
  enterprise_project_id = var.enterprise_project_id

  # VPC attachment: the gateway lives directly in the VPC (vpc_id + connect_subnet).
  vpc_id         = each.value.attachment == "vpc" ? var.vpc_ids[each.value.vpc] : null
  local_subnets  = each.value.attachment == "vpc" ? each.value.local_subnets : null
  connect_subnet = each.value.attachment == "vpc" && each.value.connect_subnet != "" ? var.subnet_ids["${each.value.vpc}__${each.value.connect_subnet}"] : null

  # ER attachment: the gateway still needs an access VPC + subnet (its interconnection
  # plane) - Huawei rejects an ER gateway without access_vpc_id. Reuse VPC/ConnectSubnet.
  er_id            = each.value.attachment == "er" ? var.er_id : null
  access_vpc_id    = each.value.attachment == "er" && each.value.vpc != "" ? var.vpc_ids[each.value.vpc] : null
  access_subnet_id = each.value.attachment == "er" && each.value.connect_subnet != "" ? var.subnet_ids["${each.value.vpc}__${each.value.connect_subnet}"] : null

  # Public gateway: create the active (eip1) + standby (eip2) EIPs.
  dynamic "eip1" {
    for_each = each.value.network_type == "public" ? [1] : []
    content {
      type           = "5_bgp"
      bandwidth_name = "${each.value.name}-eip1"
      bandwidth_size = each.value.bandwidth_size
      charge_mode    = each.value.eip_charge_mode
    }
  }
  dynamic "eip2" {
    for_each = each.value.network_type == "public" ? [1] : []
    content {
      type           = "5_bgp"
      bandwidth_name = "${each.value.name}-eip2"
      bandwidth_size = each.value.bandwidth_size
      charge_mode    = each.value.eip_charge_mode
    }
  }
}

# ---- ER routing for er-attached gateways ----
# association steers traffic arriving from on-prem (hybrid route table);
# propagation publishes the on-prem routes. On-prem routes enter ER route
# tables via propagation only.

resource "huaweicloud_er_association" "gw" {
  for_each = {
    for g in var.gateways : g.name => g
    if g.attachment == "er" && g.er_association_route_table != ""
  }

  instance_id    = var.er_id
  route_table_id = var.er_route_table_ids[each.value.er_association_route_table]
  attachment_id  = huaweicloud_vpn_gateway.this[each.key].er_attachment_id
}

resource "huaweicloud_er_propagation" "gw" {
  for_each = {
    for g in var.gateways : g.name => g
    if g.attachment == "er" && g.er_propagation_route_table != ""
  }

  instance_id    = var.er_id
  route_table_id = var.er_route_table_ids[each.value.er_propagation_route_table]
  attachment_id  = huaweicloud_vpn_gateway.this[each.key].er_attachment_id
}

# ---- Customer gateways (on-prem devices) ----

resource "huaweicloud_vpn_customer_gateway" "this" {
  for_each = { for c in var.customer_gateways : c.name => c }

  name       = each.value.name
  ip         = each.value.ip
  asn        = each.value.asn
  route_mode = each.value.route_mode
}

# ---- IPsec connections ----

resource "huaweicloud_vpn_connection" "this" {
  for_each = { for c in var.connections : c.name => c }

  name       = each.value.name
  gateway_id = huaweicloud_vpn_gateway.this[each.value.gateway].id
  # gateway_ip = the gateway EIP ID for this connection's ha_role (master=eip1, slave=eip2).
  gateway_ip = each.value.ha_role == "slave" ? (
    huaweicloud_vpn_gateway.this[each.value.gateway].eip2[0].id
    ) : (
    huaweicloud_vpn_gateway.this[each.value.gateway].eip1[0].id
  )
  vpn_type            = each.value.vpn_type
  customer_gateway_id = huaweicloud_vpn_customer_gateway.this[each.value.customer_gateway].id
  peer_subnets        = length(each.value.peer_subnets) > 0 ? each.value.peer_subnets : null
  psk                 = sensitive(each.value.psk)
  ha_role             = each.value.ha_role
}
