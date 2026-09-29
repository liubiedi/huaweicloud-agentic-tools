# --- Spoke network resources ---

# --- Spoke VPC and subnets ---
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
  # Subnet DNS servers
  # Note: Isolated spokes retain regional DNS because the hub resolver is unreachable.
  primary_dns   = var.spoke_er_attach_enabled && length(var.subnet_dns) > 0 ? var.subnet_dns[0] : null
  secondary_dns = var.spoke_er_attach_enabled && length(var.subnet_dns) > 1 ? var.subnet_dns[1] : null
  tags          = each.value.tags
}

# --- Spoke default route ---
# Note: Created only when the spoke is attached to ER.
resource "huaweicloud_vpc_route" "spoke" {
  count = local.spoke_enabled && var.spoke_er_attach_enabled ? 1 : 0

  vpc_id      = huaweicloud_vpc.spoke[0].id
  destination = "0.0.0.0/0"
  type        = "er"
  nexthop     = var.spoke_er_id

  # Note: The VPC must be attached before its ER route is created.
  depends_on = [huaweicloud_er_vpc_attachment.spoke]
}

# --- Spoke ER attachment ---
# Note: Disabling attachment isolates the spoke from the hub and other spokes.

resource "huaweicloud_er_vpc_attachment" "spoke" {
  count = local.spoke_enabled && var.spoke_er_attach_enabled ? 1 : 0

  instance_id            = var.spoke_er_id
  vpc_id                 = huaweicloud_vpc.spoke[0].id
  subnet_id              = huaweicloud_vpc_subnet.spoke[local.spoke_er_attach_subnet].id
  name                   = var.spoke_er_attachment_name != "" ? var.spoke_er_attachment_name : "att-${var.spoke_vpc_name}"
  auto_create_vpc_routes = var.spoke_auto_add_route
  tags                   = var.spoke_vpc_tags

  # Note: Attachment retagging is an owner-side operation; ignore tag drift here.
  lifecycle {
    ignore_changes = [tags]
  }
}

# --- Hub-owned spoke routing ---
# Note: Associations and propagations use the huaweicloud.owner provider.
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

# --- Baseline security group ---

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

# --- Spoke VPC flow logs ---

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
