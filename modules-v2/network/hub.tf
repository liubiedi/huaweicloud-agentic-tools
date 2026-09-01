# Hub-side resources. Gated by local.hub_enabled.

# ---- Hub VPCs ----

resource "huaweicloud_vpc" "hub" {
  for_each = local.effective_hub_vpcs

  name = each.key
  cidr = each.value.cidr
  tags = var.tags
}

resource "huaweicloud_vpc_subnet" "hub" {
  for_each = local.hub_enabled ? { for s in local.hub_subnets_flat : s.key => s } : {}

  vpc_id     = huaweicloud_vpc.hub[each.value.vpc_name].id
  name       = each.value.name
  cidr       = each.value.cidr
  gateway_ip = cidrhost(each.value.cidr, 1)
  # Central resolver via DHCP (hub-resolver DNS pattern); updates in place.
  primary_dns   = length(var.subnet_dns) > 0 ? var.subnet_dns[0] : null
  secondary_dns = length(var.subnet_dns) > 1 ? var.subnet_dns[1] : null
  tags          = var.tags
}

# ---- Enterprise Router ----

resource "huaweicloud_er_instance" "hub" {
  count = local.hub_enabled ? 1 : 0

  name                           = var.er_name
  asn                            = var.er_asn
  availability_zones             = var.er_availability_zones
  auto_accept_shared_attachments = var.er_auto_accept_shared_attachments
  enable_default_propagation     = false
  enable_default_association     = false
  enterprise_project_id          = var.enterprise_project_id

  tags = var.tags
}

# ER routing - fully AUTO-wired (standard inspection topology). ER default
# association/propagation is disabled; the wiring below carries all HUB routing,
# and spokes self-wire the same way (spoke.tf). No per-row association/
# propagation/static-route inputs.

resource "huaweicloud_er_route_table" "rt" {
  for_each = local.hub_enabled ? { for rt in var.er_route_tables : rt.name => rt } : {}

  instance_id = huaweicloud_er_instance.hub[0].id
  name        = each.key
  tags        = var.tags
}

resource "huaweicloud_er_vpc_attachment" "hub" {
  for_each = local.hub_enabled ? { for a in var.er_attachments : a.name => a } : {}

  instance_id            = huaweicloud_er_instance.hub[0].id
  vpc_id                 = huaweicloud_vpc.hub[each.value.vpc].id
  subnet_id              = huaweicloud_vpc_subnet.hub["${each.value.vpc}__${each.value.subnet != "" ? each.value.subnet : var.hub_vpcs[each.value.vpc].subnets[0].name}"].id
  name                   = each.value.name
  auto_create_vpc_routes = each.value.auto_add_route
  tags                   = var.tags
}

# ---- Auto-wiring (standard inspection topology) ----
# Every hub VPC attachment associates to the inbound route table and propagates
# into the outbound one; the CFW attachment associates to the outbound table.
# Spokes wire themselves the same way (spoke.tf).
resource "huaweicloud_er_association" "hub_vpc" {
  for_each = local.hub_enabled && var.inbound_route_table != "" ? { for a in var.er_attachments : a.name => a } : {}

  instance_id    = huaweicloud_er_instance.hub[0].id
  route_table_id = huaweicloud_er_route_table.rt[var.inbound_route_table].id
  attachment_id  = huaweicloud_er_vpc_attachment.hub[each.key].id
}

resource "huaweicloud_er_propagation" "hub_vpc" {
  for_each = local.hub_enabled && var.outbound_route_table != "" ? { for a in var.er_attachments : a.name => a } : {}

  instance_id    = huaweicloud_er_instance.hub[0].id
  route_table_id = huaweicloud_er_route_table.rt[var.outbound_route_table].id
  attachment_id  = huaweicloud_er_vpc_attachment.hub[each.key].id
}

resource "huaweicloud_er_association" "cfw" {
  count = local.hub_enabled && var.outbound_route_table != "" ? 1 : 0

  instance_id    = huaweicloud_er_instance.hub[0].id
  route_table_id = huaweicloud_er_route_table.rt[var.outbound_route_table].id
  attachment_id  = huaweicloud_cfw_firewall.hub[0].east_west_firewall_er_attachment_id
}

# ---- Auto static routes ----
# inbound  0.0.0.0/0 -> CFW attachment        (force everything through inspection)
# outbound 0.0.0.0/0 -> snat_vpc_attachment   (post-inspection internet egress to NAT)
resource "huaweicloud_er_static_route" "inbound_to_cfw" {
  count = local.hub_enabled && var.inbound_route_table != "" ? 1 : 0

  route_table_id = huaweicloud_er_route_table.rt[var.inbound_route_table].id
  destination    = "0.0.0.0/0"
  attachment_id  = huaweicloud_cfw_firewall.hub[0].east_west_firewall_er_attachment_id
}

resource "huaweicloud_er_static_route" "outbound_to_snat" {
  count = local.hub_enabled && var.outbound_route_table != "" && var.snat_vpc_attachment != "" ? 1 : 0

  route_table_id = huaweicloud_er_route_table.rt[var.outbound_route_table].id
  destination    = "0.0.0.0/0"
  attachment_id  = huaweicloud_er_vpc_attachment.hub[var.snat_vpc_attachment].id
}

# Dedicated hybrid route tables (VPN/DC): same 0.0.0.0/0 -> CFW route as the
# inbound RT, so on-prem traffic entering via a VPN/DC attachment associated to
# one of these tables is inspected before reaching any VPC.
resource "huaweicloud_er_static_route" "extra_to_cfw" {
  for_each = local.hub_enabled ? toset([
    for rt in var.cfw_default_route_tables : rt if rt != var.inbound_route_table
  ]) : toset([])

  route_table_id = huaweicloud_er_route_table.rt[each.value].id
  destination    = "0.0.0.0/0"
  attachment_id  = huaweicloud_cfw_firewall.hub[0].east_west_firewall_er_attachment_id
}

# The same route for the private supernet. Required, not redundant: VPN peers
# do not reliably receive the 0.0.0.0/0 route, so this is the route on-prem
# actually learns for reaching the cloud.
resource "huaweicloud_er_static_route" "extra_supernet_to_cfw" {
  for_each = local.hub_enabled && var.spoke_private_supernet != "" ? toset([
    for rt in var.cfw_default_route_tables : rt if rt != var.inbound_route_table
  ]) : toset([])

  route_table_id = huaweicloud_er_route_table.rt[each.value].id
  destination    = var.spoke_private_supernet
  attachment_id  = huaweicloud_cfw_firewall.hub[0].east_west_firewall_er_attachment_id
}

# ---- VPC flow logs -> own LTS group/stream '<vpc>-flowlog' per hub VPC ----
# Uniform with the spoke pattern; module 12 aggregates via LogConverge rows.

resource "huaweicloud_lts_group" "hub_flow" {
  for_each = local.hub_enabled && var.enable_vpc_flow_logs ? local.effective_hub_vpcs : {}

  group_name            = "${each.key}-flowlog"
  ttl_in_days           = var.flow_log_retention_days
  enterprise_project_id = var.enterprise_project_id
  tags                  = var.tags
}

resource "huaweicloud_lts_stream" "hub_flow" {
  for_each = local.hub_enabled && var.enable_vpc_flow_logs ? local.effective_hub_vpcs : {}

  group_id    = huaweicloud_lts_group.hub_flow[each.key].id
  stream_name = "${each.key}-flowlog"
  ttl_in_days = var.flow_log_retention_days
  tags        = var.tags
}

resource "huaweicloud_vpc_flow_log" "hub" {
  for_each = local.hub_enabled && var.enable_vpc_flow_logs ? local.effective_hub_vpcs : {}

  name          = "${each.key}-flow-log"
  resource_type = "vpc"
  resource_id   = huaweicloud_vpc.hub[each.key].id
  traffic_type  = "all"
  log_group_id  = huaweicloud_lts_group.hub_flow[each.key].id
  log_stream_id = huaweicloud_lts_stream.hub_flow[each.key].id
}

# ---- CFW / ER log destination (LTS) ----
# When cfw_lts_log_enable=true the hub creates one LTS group + THREE streams -
# one per CFW log type (traffic/flow, access, attack). Passing cfw_lts_group_id
# reuses an existing group; the three streams are still created in it.
locals {
  _cfw_lts_enabled  = local.hub_enabled && var.cfw_lts_log_enable
  _create_cfw_group = local._cfw_lts_enabled && var.cfw_lts_group_id == ""

  cfw_lts_group_id_effective = var.cfw_lts_group_id != "" ? var.cfw_lts_group_id : (local._create_cfw_group ? huaweicloud_lts_group.cfw[0].id : "")
}

resource "huaweicloud_lts_group" "cfw" {
  count = local._create_cfw_group ? 1 : 0

  group_name            = var.cfw_lts_log_group_name
  ttl_in_days           = 30
  enterprise_project_id = var.enterprise_project_id
  tags                  = var.tags
}

# One LTS stream per CFW log type. Keyed traffic | access | attack.
resource "huaweicloud_lts_stream" "cfw" {
  for_each = local._cfw_lts_enabled ? {
    traffic = var.cfw_lts_traffic_stream_name
    access  = var.cfw_lts_access_stream_name
    attack  = var.cfw_lts_attack_stream_name
  } : {}

  group_id    = local.cfw_lts_group_id_effective
  stream_name = each.value
  tags        = var.tags
}

# ER attachment flow log -> the traffic stream.
resource "huaweicloud_er_flow_log" "hub" {
  count = local._cfw_lts_enabled && length(var.er_attachments) > 0 ? 1 : 0

  instance_id   = huaweicloud_er_instance.hub[0].id
  resource_type = "attachment"
  # Monitor the first ER attachment (sorted by name for determinism).
  resource_id    = huaweicloud_er_vpc_attachment.hub[sort(keys(huaweicloud_er_vpc_attachment.hub))[0]].id
  log_store_type = "LTS"
  log_group_id   = local.cfw_lts_group_id_effective
  log_stream_id  = huaweicloud_lts_stream.cfw["traffic"].id
  name           = var.er_flow_log_name
}

# ---- Cloud Firewall ----

resource "huaweicloud_cfw_firewall" "hub" {
  count = local.hub_enabled ? 1 : 0

  name = var.cfw_name

  flavor {
    # Normalize the edition name to the capitalized form the API expects.
    version = lookup({ standard = "Standard", professional = "Professional" }, lower(var.cfw_flavor), var.cfw_flavor)
  }

  # East-west firewall in ER mode: CFW gets its own ER attachment
  # (east_west_firewall_er_attachment_id) and traffic is steered through it via
  # the ER route tables. All three args are immutable after creation.
  east_west_firewall_er_id           = huaweicloud_er_instance.hub[0].id
  east_west_firewall_inspection_cidr = var.inspection_cidr_reservation
  east_west_firewall_mode            = var.east_west_firewall_mode

  enterprise_project_id = var.enterprise_project_id

  # Map the spec's pay-per-use|subscription to the provider's postPaid|prePaid.
  charging_mode = local._cfw_prepaid ? "prePaid" : "postPaid"
  period_unit   = local._cfw_prepaid ? var.cfw_period_unit : null
  period        = local._cfw_prepaid ? var.cfw_period : null
  auto_renew    = local._cfw_prepaid ? tostring(var.cfw_auto_renew) : null
  tags          = var.tags

  # IPS attack defense (null = console-managed). Mode: 0 observe, 1 strict,
  # 2 medium, 3 loose; ips_switch_status is the virtual-patching switch.
  ips_protection_mode = var.cfw_ips_protection_mode
  ips_switch_status   = var.cfw_ips_patch_enabled == null ? null : (var.cfw_ips_patch_enabled ? 1 : 0)
}

locals {
  _cfw_prepaid = var.cfw_charging_mode == "subscription"
}

resource "huaweicloud_cfw_address_group" "hub" {
  for_each = local.hub_enabled ? { for g in var.cfw_address_groups : g.name => g } : {}

  object_id   = huaweicloud_cfw_firewall.hub[0].protect_objects[0].object_id
  name        = each.key
  description = each.value.description
}

resource "huaweicloud_cfw_address_group_member" "hub" {
  for_each = local.hub_enabled ? {
    for pair in flatten([
      for g in var.cfw_address_groups : [
        for m in g.members : { key = "${g.name}__${m}", group = g.name, address = m }
      ]
    ]) : pair.key => pair
  } : {}

  group_id = huaweicloud_cfw_address_group.hub[each.value.group].id
  address  = each.value.address
}

resource "huaweicloud_cfw_service_group" "hub" {
  for_each = local.hub_enabled ? { for g in var.cfw_service_groups : g.name => g } : {}

  object_id   = huaweicloud_cfw_firewall.hub[0].protect_objects[0].object_id
  name        = each.key
  description = each.value.description
}

resource "huaweicloud_cfw_service_group_member" "hub" {
  for_each = local.hub_enabled ? {
    for pair in flatten([
      for g in var.cfw_service_groups : [
        for idx, m in g.members : { key = "${g.name}__${idx}", group = g.name, member = m }
      ]
    ]) : pair.key => pair
  } : {}

  group_id    = huaweicloud_cfw_service_group.hub[each.value.group].id
  protocol    = each.value.member.protocol
  source_port = each.value.member.source_port
  dest_port   = each.value.member.dest_port
}

resource "huaweicloud_cfw_lts_log" "hub" {
  count = local._cfw_lts_enabled ? 1 : 0

  fw_instance_id   = huaweicloud_cfw_firewall.hub[0].id
  lts_log_group_id = local.cfw_lts_group_id_effective

  lts_attack_log_stream_enable = 1
  lts_access_log_stream_enable = 1
  lts_flow_log_stream_enable   = 1

  lts_attack_log_stream_id = huaweicloud_lts_stream.cfw["attack"].id
  lts_access_log_stream_id = huaweicloud_lts_stream.cfw["access"].id
  lts_flow_log_stream_id   = huaweicloud_lts_stream.cfw["traffic"].id
}

# ---- EIPs + public NAT gateways (multi-instance) ----
# EIPs, NAT gateways and ELBs are multi-instance. SNAT/DNAT resolve a NAT by
# name and an EIP by name; nat-type VPC routes resolve a NAT by name; ELB
# pools/listeners resolve an ELB by name. A blank NAT/ELB name falls back to the
# sole instance (the common single-NAT / single-ELB hub).

locals {
  _sole_nat = length(var.nat_gateways) > 0 ? var.nat_gateways[0].name : ""
  _sole_elb = length(var.elbs) > 0 ? var.elbs[0].name : ""
}

# Each EIP gets its own dedicated bandwidth (share_type PER). billed_by selects
# bandwidth vs traffic metering. charging_mode is left unset here and on the NAT
# gateway below, so both follow whatever billing mode BSS holds.
resource "huaweicloud_vpc_eip" "this" {
  for_each = local.hub_enabled ? { for e in var.eips : e.name => e } : {}

  publicip {
    type = each.value.type
  }
  bandwidth {
    share_type  = "PER"
    name        = "${each.value.name}-bw"
    size        = each.value.bandwidth_size
    charge_mode = each.value.billed_by
  }
  enterprise_project_id = var.enterprise_project_id
  tags                  = var.tags
}

resource "huaweicloud_natv3_gateway" "hub" {
  for_each = local.hub_enabled ? { for n in var.nat_gateways : n.name => n } : {}

  name = each.value.name
  # Map the friendly size names to the API's numeric spec (numeric passes through).
  spec                  = lookup({ Small = "1", Medium = "2", Large = "3", "Extra-large" = "4" }, each.value.spec, each.value.spec)
  vpc_id                = huaweicloud_vpc.hub[each.value.vpc].id
  subnet_id             = huaweicloud_vpc_subnet.hub["${each.value.vpc}__${each.value.subnet != "" ? each.value.subnet : var.hub_vpcs[each.value.vpc].subnets[0].name}"].id
  enterprise_project_id = var.enterprise_project_id
  tags                  = var.tags
}

# ---- SNAT rules (egress) ----

resource "huaweicloud_nat_snat_rule" "hub" {
  for_each = local.hub_enabled ? { for idx, r in var.snat_rules : "${idx}-${r.cidr}" => r } : {}

  nat_gateway_id = huaweicloud_natv3_gateway.hub[each.value.nat_name != "" ? each.value.nat_name : local._sole_nat].id
  floating_ip_id = huaweicloud_vpc_eip.this[each.value.eip].id
  cidr           = each.value.cidr
  description    = each.value.description
}

# ---- DNAT rules (ingress) ----

resource "huaweicloud_nat_dnat_rule" "hub" {
  for_each = local.hub_enabled ? {
    for idx, r in var.dnat_rules :
    "${r.protocol}-${r.external_port}" => r
  } : {}

  nat_gateway_id        = huaweicloud_natv3_gateway.hub[each.value.nat_name != "" ? each.value.nat_name : local._sole_nat].id
  floating_ip_id        = huaweicloud_vpc_eip.this[each.value.eip].id
  external_service_port = each.value.external_port
  private_ip            = each.value.internal_ip
  internal_service_port = each.value.internal_port
  protocol              = each.value.protocol
  description           = each.value.description
}

# ---- Hub VPC default-route tables (auto) ----
# Every ER-attached hub VPC gets 0.0.0.0/0 -> hub ER, EXCEPT the SNAT VPC (the
# one hosting the egress NAT, from snat_vpc_attachment) which instead gets:
#   0.0.0.0/0          -> its NAT gateway  (internet egress)
#   <private supernet> -> ER               (return path to spokes; more specific,
#                                            so it wins over the NAT default)
locals {
  # The hub VPC that hosts the egress NAT (resolved from the snat_vpc_attachment
  # ER attachment), and the NAT gateway in that VPC.
  _snat_vpc = var.snat_vpc_attachment != "" ? try(
  [for a in var.er_attachments : a.vpc if a.name == var.snat_vpc_attachment][0], "") : ""
  _snat_nat = local._snat_vpc != "" ? try(
  [for n in var.nat_gateways : n.name if n.vpc == local._snat_vpc][0], "") : ""

  # Hub VPCs that attach to the ER (only these can route to it).
  _hub_attached_vpcs = distinct([for a in var.er_attachments : a.vpc])

  _hub_routes = local.hub_enabled ? flatten([
    for v in local._hub_attached_vpcs : (
      v == local._snat_vpc
      ? concat(
        local._snat_nat != "" ? [{ vpc = v, destination = "0.0.0.0/0", to = "nat" }] : [],
        var.spoke_private_supernet != "" ? [{ vpc = v, destination = var.spoke_private_supernet, to = "er" }] : [],
      )
      : [{ vpc = v, destination = "0.0.0.0/0", to = "er" }]
    )
  ]) : []
}

resource "huaweicloud_vpc_route" "hub" {
  for_each = { for r in local._hub_routes : "${r.vpc}__${r.destination}" => r }

  vpc_id      = huaweicloud_vpc.hub[each.value.vpc].id
  destination = each.value.destination
  type        = each.value.to == "nat" ? "nat" : "er"
  nexthop = (
    each.value.to == "nat"
    ? huaweicloud_natv3_gateway.hub[local._snat_nat].id
    : huaweicloud_er_instance.hub[0].id
  )

  # A VPC can only route to an ER it is attached to.
  depends_on = [huaweicloud_er_vpc_attachment.hub]
}

# ---- ELB - dedicated, IPv4, elastic spec (multi-instance) ----
# Flavor IDs are intentionally unset -> the LB is created as elastic
# (pay-per-use, autoscaling). EIP name (if set) binds a public EIP from
# var.eips. ip_as_backend -> cross_vpc_backend (IP-as-backend / cross-VPC).

resource "huaweicloud_elb_loadbalancer" "ingress" {
  for_each = local.hub_enabled ? { for e in var.elbs : e.name => e } : {}

  name              = each.value.name
  vpc_id            = huaweicloud_vpc.hub[each.value.vpc].id
  ipv4_subnet_id    = huaweicloud_vpc_subnet.hub["${each.value.vpc}__${each.value.frontend_subnet != "" ? each.value.frontend_subnet : var.hub_vpcs[each.value.vpc].subnets[0].name}"].ipv4_subnet_id
  availability_zone = length(each.value.azs) > 0 ? each.value.azs : var.er_availability_zones
  cross_vpc_backend = each.value.ip_as_backend
  backend_subnets = each.value.backend_subnet != "" ? [
    huaweicloud_vpc_subnet.hub["${each.value.vpc}__${each.value.backend_subnet}"].ipv4_subnet_id
  ] : null
  ipv4_eip_id           = each.value.eip != "" ? huaweicloud_vpc_eip.this[each.value.eip].id : null
  enterprise_project_id = var.enterprise_project_id
  tags                  = var.tags
}

resource "huaweicloud_elb_pool" "ingress" {
  for_each = local.hub_enabled ? { for p in var.elb_pools : p.name => p } : {}

  name            = each.value.name
  protocol        = each.value.protocol
  lb_method       = each.value.lb_method
  loadbalancer_id = huaweicloud_elb_loadbalancer.ingress[each.value.loadbalancer_name != "" ? each.value.loadbalancer_name : local._sole_elb].id
  description     = each.value.description
}

resource "huaweicloud_elb_listener" "ingress" {
  for_each = local.hub_enabled ? { for l in var.elb_listeners : l.name => l } : {}

  name            = each.value.name
  protocol        = each.value.protocol
  protocol_port   = each.value.protocol_port
  loadbalancer_id = huaweicloud_elb_loadbalancer.ingress[each.value.loadbalancer_name != "" ? each.value.loadbalancer_name : local._sole_elb].id
  default_pool_id = huaweicloud_elb_pool.ingress[each.value.default_pool_name].id
}

resource "huaweicloud_elb_monitor" "ingress" {
  # Keyed on the input pool names so for_each keys are known at plan time.
  for_each = local.hub_enabled ? { for p in var.elb_pools : p.name => p } : {}

  pool_id     = huaweicloud_elb_pool.ingress[each.key].id
  protocol    = "HTTP"
  interval    = 5
  timeout     = 3
  max_retries = 3
}

resource "huaweicloud_elb_logtank" "ingress" {
  for_each = local.hub_enabled && var.elb_lts_group_id != "" ? { for e in var.elbs : e.name => e } : {}

  loadbalancer_id = huaweicloud_elb_loadbalancer.ingress[each.key].id
  log_group_id    = var.elb_lts_group_id
  log_topic_id    = var.elb_lts_stream_id
}

# ---- RAM share - ER attachment to spoke accounts ----
# Org-level RAM enablement is a master-account operation and lives in the env;
# this module (member account) creates the share itself.

# Resolve the permission for the ER resource type ("er:instances").
data "huaweicloud_ram_resource_permissions" "er" {
  count         = local.hub_enabled && length(var.ram_share_principals) > 0 ? 1 : 0
  resource_type = "er:instances"
}

resource "huaweicloud_ram_resource_share" "er_attachment" {
  count = local.hub_enabled && length(var.ram_share_principals) > 0 ? 1 : 0

  name = var.er_share_name
  # RAM takes full URNs: er:<region>:<owner-account-id>:instances:<er-id>.
  resource_urns = [
    format(
      "er:%s:%s:instances:%s",
      huaweicloud_er_instance.hub[0].region,
      var.er_share_owner_account_id,
      huaweicloud_er_instance.hub[0].id,
    )
  ]
  principals     = var.ram_share_principals
  permission_ids = [data.huaweicloud_ram_resource_permissions.er[0].permissions[0].id]

  # Keep the share org-internal (also required by the RAM guardrail SCP).
  allow_external_principals = false

  tags = var.tags
}

# RAM share association propagates asynchronously; spokes wait on this sleep,
# which is replaced whenever the principal set changes.
resource "time_sleep" "ram_share_propagation" {
  count = local.hub_enabled && length(var.ram_share_principals) > 0 ? 1 : 0

  create_duration = "60s"

  triggers = {
    share_id   = huaweicloud_ram_resource_share.er_attachment[0].id
    principals = join(",", sort(var.ram_share_principals))
  }
}
