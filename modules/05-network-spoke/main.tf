locals {
  tags = merge({
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Layer     = "network-spoke"
    SpokeName = var.spoke_name
  }, var.tags)
}

# ── Spoke VPC ─────────────────────────────────────────────────────────────────

resource "huaweicloud_vpc" "spoke" {
  name   = "${var.spoke_name}-vpc"
  cidr   = var.vpc_cidr
  region = var.home_region
  tags   = local.tags
}

# ── Application subnets ───────────────────────────────────────────────────────

resource "huaweicloud_vpc_subnet" "subnets" {
  for_each = { for s in var.subnets : s.name => s }

  name              = "${var.spoke_name}-${each.value.name}"
  cidr              = each.value.cidr
  gateway_ip        = cidrhost(each.value.cidr, 1)
  vpc_id            = huaweicloud_vpc.spoke.id
  availability_zone = each.value.zone
  description       = each.value.description
  region            = var.home_region
  tags              = local.tags
}

# ── ER attachment subnet ──────────────────────────────────────────────────────

resource "huaweicloud_vpc_subnet" "er_attach" {
  name       = "${var.spoke_name}-er-attach"
  cidr       = var.er_attach_subnet_cidr
  gateway_ip = cidrhost(var.er_attach_subnet_cidr, 1)
  vpc_id     = huaweicloud_vpc.spoke.id
  availability_zone = var.er_attach_zone
  region     = var.home_region
  tags       = local.tags
}

# ── ER VPC attachment ─────────────────────────────────────────────────────────

resource "huaweicloud_er_vpc_attachment" "spoke" {
  instance_id = var.er_instance_id
  vpc_id      = huaweicloud_vpc.spoke.id
  subnet_id   = huaweicloud_vpc_subnet.er_attach.id
  name        = "${var.spoke_name}-er-attach"
  region      = var.home_region
}

# ── Default route via ER ──────────────────────────────────────────────────────

resource "huaweicloud_vpc_route_table" "spoke" {
  name    = "${var.spoke_name}-rt"
  vpc_id  = huaweicloud_vpc.spoke.id
  subnets = concat(
    [for s in huaweicloud_vpc_subnet.subnets : s.id],
    [huaweicloud_vpc_subnet.er_attach.id]
  )
  region = var.home_region

  route {
    type        = "er"
    destination = var.hub_cidr
    nexthop     = var.er_instance_id
  }
}

# ── VPC Flow Log ──────────────────────────────────────────────────────────────

resource "huaweicloud_vpc_flow_log" "spoke" {
  count = var.lts_log_group_id != "" ? 1 : 0

  name          = "${var.spoke_name}-vpc-flowlog"
  resource_type = "vpc"
  resource_id   = huaweicloud_vpc.spoke.id
  traffic_type  = "all"
  log_group_id  = var.lts_log_group_id
  log_stream_id = var.lts_log_stream_id
}

# ── Baseline Security Group ───────────────────────────────────────────────────

resource "huaweicloud_networking_secgroup" "baseline" {
  count = var.enable_security_group ? 1 : 0

  name                 = "${var.spoke_name}-baseline-sg"
  description          = "Baseline security group for ${var.spoke_name}"
  delete_default_rules = true
  region               = var.home_region
  tags                 = local.tags
}

resource "huaweicloud_networking_secgroup_rule" "allow_intra_vpc" {
  count = var.enable_security_group ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.vpc_cidr
  security_group_id = huaweicloud_networking_secgroup.baseline[0].id
  region            = var.home_region
}

resource "huaweicloud_networking_secgroup_rule" "allow_hub" {
  count = var.enable_security_group ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "10.0.0.0/8"
  security_group_id = huaweicloud_networking_secgroup.baseline[0].id
  description       = "Allow inbound from hub and other spokes"
  region            = var.home_region
}

resource "huaweicloud_networking_secgroup_rule" "egress_all" {
  count = var.enable_security_group ? 1 : 0

  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.baseline[0].id
  region            = var.home_region
}
