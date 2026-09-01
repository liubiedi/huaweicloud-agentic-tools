# Spoke-side resources. Gated by local.spoke_enabled.
# Called once per spoke account via provider alias.

# Spoke resources carry only their explicit per-row tags - the spoke
# provider omits default_tags so workload accounts don't inherit the hub's
# Global cost-center tags.
resource "huaweicloud_vpc" "spoke" {
  count = local.spoke_enabled ? 1 : 0

  name = var.spoke_vpc_name
  cidr = var.spoke_vpc_cidr
  tags = var.spoke_vpc_tags
}

resource "huaweicloud_vpc_subnet" "spoke" {
  for_each = local.spoke_enabled ? { for s in var.spoke_subnets : s.name => s } : {}

  vpc_id     = huaweicloud_vpc.spoke[0].id
  name       = each.value.name
  cidr       = each.value.cidr
  gateway_ip = cidrhost(each.value.cidr, 1)
  # Central resolver via DHCP (hub-resolver DNS pattern); updates in place.
  # Skipped for UNATTACHED spokes: the resolver is only reachable over the ER,
  # so an isolated spoke would black-hole ALL DNS. Left unset, the provider
  # applies the region's built-in resolver instead.
  primary_dns   = var.spoke_er_attach_enabled && length(var.subnet_dns) > 0 ? var.subnet_dns[0] : null
  secondary_dns = var.spoke_er_attach_enabled && length(var.subnet_dns) > 1 ? var.subnet_dns[1] : null
  tags          = each.value.tags
}

# Spoke VPC default route (auto): everything to the hub ER for inspection.
# Skipped for UNATTACHED spokes (spoke_er_attach_enabled = false) - no ER, no route.
resource "huaweicloud_vpc_route" "spoke" {
  count = local.spoke_enabled && var.spoke_er_attach_enabled ? 1 : 0

  vpc_id      = huaweicloud_vpc.spoke[0].id
  destination = "0.0.0.0/0"
  type        = "er"
  nexthop     = var.spoke_er_id

  # A VPC can only route to an ER it is attached to.
  depends_on = [huaweicloud_er_vpc_attachment.spoke]
}

# ---- Spoke ER attachment (on the first subnet) ----
# spoke_er_attach_enabled=false = isolated spoke: VPC/subnets/SG exist, but no ER
# attachment/route/association/propagation - unreachable from hub and other spokes.

resource "huaweicloud_er_vpc_attachment" "spoke" {
  count = local.spoke_enabled && var.spoke_er_attach_enabled ? 1 : 0

  instance_id            = var.spoke_er_id
  vpc_id                 = huaweicloud_vpc.spoke[0].id
  subnet_id              = huaweicloud_vpc_subnet.spoke[local.spoke_er_attach_subnet].id
  name                   = var.spoke_er_attachment_name != "" ? var.spoke_er_attachment_name : "att-${var.spoke_vpc_name}"
  auto_create_vpc_routes = var.spoke_auto_add_route
  tags                   = var.spoke_vpc_tags

  # Attachment tags apply at create only; post-create retagging is an
  # owner-side operation, so tag drift is ignored here.
  lifecycle {
    ignore_changes = [tags]
  }
}

# ---- Spoke ER wiring against the hub route tables (OWNER provider) ----
# The ER and its route tables live in the hub account; only the owner can
# manage associations and propagations, so they run under huaweicloud.owner
# (the hub provider passed in by the environment).
resource "huaweicloud_er_association" "spoke" {
  provider = huaweicloud.owner
  count    = local.spoke_enabled && var.spoke_er_attach_enabled && var.inbound_route_table != "" ? 1 : 0

  instance_id    = var.spoke_er_id
  route_table_id = var.hub_route_table_ids[var.inbound_route_table]
  attachment_id  = huaweicloud_er_vpc_attachment.spoke[0].id
}

resource "huaweicloud_er_propagation" "spoke" {
  provider = huaweicloud.owner
  count    = local.spoke_enabled && var.spoke_er_attach_enabled && var.outbound_route_table != "" ? 1 : 0

  instance_id    = var.spoke_er_id
  route_table_id = var.hub_route_table_ids[var.outbound_route_table]
  attachment_id  = huaweicloud_er_vpc_attachment.spoke[0].id
}

# ---- Baseline security group ----

resource "huaweicloud_networking_secgroup" "baseline" {
  count = local.spoke_enabled ? 1 : 0

  name        = var.spoke_secgroup_name != "" ? var.spoke_secgroup_name : "${var.spoke_vpc_name}-baseline"
  description = "Baseline workload SG: egress all, ingress within VPC"
}

resource "huaweicloud_networking_secgroup_rule" "egress_all" {
  count = local.spoke_enabled ? 1 : 0

  security_group_id = huaweicloud_networking_secgroup.baseline[0].id
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "huaweicloud_networking_secgroup_rule" "ingress_within_vpc" {
  count = local.spoke_enabled ? 1 : 0

  security_group_id = huaweicloud_networking_secgroup.baseline[0].id
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.spoke_vpc_cidr
}

# ---- VPC flow log -> own LTS group/stream '<vpc>-flowlog' ----
# Per-VPC group (not per account): two spokes in the same account would otherwise
# race on one group name. Module 12 picks these up via LogConverge rows.

resource "huaweicloud_lts_group" "spoke_flow" {
  count = local.spoke_enabled && var.enable_vpc_flow_logs ? 1 : 0

  group_name  = "${var.spoke_vpc_name}-flowlog"
  ttl_in_days = var.flow_log_retention_days
  tags        = var.spoke_vpc_tags
}

resource "huaweicloud_lts_stream" "spoke_flow" {
  count = local.spoke_enabled && var.enable_vpc_flow_logs ? 1 : 0

  group_id    = huaweicloud_lts_group.spoke_flow[0].id
  stream_name = "${var.spoke_vpc_name}-flowlog"
  ttl_in_days = var.flow_log_retention_days
  tags        = var.spoke_vpc_tags
}

resource "huaweicloud_vpc_flow_log" "spoke" {
  count = local.spoke_enabled && var.enable_vpc_flow_logs ? 1 : 0

  name          = "${var.spoke_vpc_name}-flow-log"
  resource_type = "vpc"
  resource_id   = huaweicloud_vpc.spoke[0].id
  traffic_type  = "all"
  log_group_id  = huaweicloud_lts_group.spoke_flow[0].id
  log_stream_id = huaweicloud_lts_stream.spoke_flow[0].id
}
