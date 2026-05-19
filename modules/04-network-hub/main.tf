locals {
  tags = merge({
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Layer     = "network-hub"
  }, var.tags)
}

# ── Hub VPC ───────────────────────────────────────────────────────────────────

resource "huaweicloud_vpc" "hub" {
  name   = "lz-hub-vpc"
  cidr   = var.hub_vpc_cidr
  region = var.home_region
  tags   = local.tags
}

resource "huaweicloud_vpc_subnet" "er_attach" {
  name       = "lz-hub-er-attach"
  cidr       = var.hub_subnet_cidr
  gateway_ip = cidrhost(var.hub_subnet_cidr, 1)
  vpc_id     = huaweicloud_vpc.hub.id
  region     = var.home_region
  tags       = local.tags
}

resource "huaweicloud_vpc_subnet" "firewall" {
  name       = "lz-hub-firewall"
  cidr       = var.firewall_subnet_cidr
  gateway_ip = cidrhost(var.firewall_subnet_cidr, 1)
  vpc_id     = huaweicloud_vpc.hub.id
  region     = var.home_region
  tags       = local.tags
}

# ── VPC Flow Log ──────────────────────────────────────────────────────────────

resource "huaweicloud_vpc_flow_log" "hub" {
  count = var.lts_log_group_id != "" ? 1 : 0

  name          = "lz-hub-vpc-flowlog"
  resource_type = "vpc"
  resource_id   = huaweicloud_vpc.hub.id
  traffic_type  = "all"
  log_group_id  = var.lts_log_group_id
  log_stream_id = var.lts_log_stream_id
}

# ── Enterprise Router ─────────────────────────────────────────────────────────

resource "huaweicloud_er_instance" "hub" {
  name                          = var.er_name
  asn                           = var.er_asn
  availability_zones            = data.huaweicloud_availability_zones.this.names
  enable_default_propagation    = true
  enable_default_association    = true
  auto_accept_shared_attachments = true
  region                        = var.home_region
  tags                          = local.tags
}

data "huaweicloud_availability_zones" "this" {
  region = var.home_region
}

resource "huaweicloud_er_vpc_attachment" "hub" {
  instance_id = huaweicloud_er_instance.hub.id
  vpc_id      = huaweicloud_vpc.hub.id
  subnet_id   = huaweicloud_vpc_subnet.er_attach.id
  name        = "lz-hub-vpc-attach"
  region      = var.home_region
}

resource "huaweicloud_er_route_table" "hub" {
  instance_id = huaweicloud_er_instance.hub.id
  name        = "lz-hub-rt"
  region      = var.home_region
  tags        = local.tags
}

resource "huaweicloud_er_association" "hub" {
  instance_id       = huaweicloud_er_instance.hub.id
  route_table_id    = huaweicloud_er_route_table.hub.id
  attachment_id     = huaweicloud_er_vpc_attachment.hub.id
  region            = var.home_region
}

resource "huaweicloud_er_propagation" "hub" {
  instance_id    = huaweicloud_er_instance.hub.id
  route_table_id = huaweicloud_er_route_table.hub.id
  attachment_id  = huaweicloud_er_vpc_attachment.hub.id
  region         = var.home_region
}

# ── ER Flow Log ───────────────────────────────────────────────────────────────

resource "huaweicloud_er_flow_log" "er" {
  count = var.lts_log_group_id != "" ? 1 : 0

  instance_id    = huaweicloud_er_instance.hub.id
  log_group_id   = var.lts_log_group_id
  log_stream_id  = var.lts_log_stream_id
  resource_type  = "attachment"
  region         = var.home_region
}

# ── RAM share ER to spokes ────────────────────────────────────────────────────

resource "huaweicloud_ram_resource_share" "er" {
  name              = "lz-er-share"
  description       = "Share ER instance to all spoke accounts"
  permission_ids    = ["huaweicloud/ram:ERFullAccess"]
  principals        = var.spoke_account_ids
  resource_type     = "er:instance"
  resource_ids      = [huaweicloud_er_instance.hub.id]
}

# ── Cloud Firewall ────────────────────────────────────────────────────────────

resource "huaweicloud_cfw_firewall" "this" {
  count = var.enable_cloud_firewall ? 1 : 0

  name   = var.cfw_name
  type   = var.cfw_type
  region = var.home_region

  flavor {
    version = "Professional"
  }

  tags = local.tags
}

resource "huaweicloud_cfw_lts_log_config" "this" {
  count = var.enable_cloud_firewall && var.lts_log_group_id != "" ? 1 : 0

  firewall_id      = huaweicloud_cfw_firewall.this[0].id
  lts_enable       = true
  log_group_id     = var.lts_log_group_id
  log_stream_id    = var.lts_log_stream_id
  region           = var.home_region
}

# ── Hub NAT Gateway ───────────────────────────────────────────────────────────

resource "huaweicloud_vpc_bandwidth" "nat" {
  name        = "lz-nat-shared-bw"
  size        = var.nat_public_eip_bandwidth
  region      = var.home_region
}

resource "huaweicloud_vpc_eip" "nat" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    share_type  = "WHOLE"
    id          = huaweicloud_vpc_bandwidth.nat.id
    charge_mode = "traffic"
  }
  region = var.home_region
  tags   = local.tags
}

resource "huaweicloud_nat_gateway" "hub" {
  name        = "lz-hub-nat"
  description = "Centralized NAT for all spoke VPCs"
  spec        = "3"
  vpc_id      = huaweicloud_vpc.hub.id
  subnet_id   = huaweicloud_vpc_subnet.er_attach.id
  region      = var.home_region
  tags        = local.tags
}

resource "huaweicloud_nat_snat_rule" "hub" {
  nat_gateway_id = huaweicloud_nat_gateway.hub.id
  floating_ip_id = huaweicloud_vpc_eip.nat.id
  source_type    = 0
  subnet_id      = huaweicloud_vpc_subnet.er_attach.id
  region         = var.home_region
}

# ── VPN Gateway (optional) ────────────────────────────────────────────────────

resource "huaweicloud_vpn_gateway" "hub" {
  count = var.enable_vpn_gateway ? 1 : 0

  name              = "lz-hub-vpn-gw"
  vpc_id            = huaweicloud_vpc.hub.id
  local_subnets     = [var.hub_subnet_cidr]
  connect_subnet    = huaweicloud_vpc_subnet.er_attach.id
  ha_mode           = "active-active"
  region            = var.home_region
  tags              = local.tags

  master_eip {
    type            = "5_bgp"
    bandwidth_name  = "lz-vpn-master-bw"
    bandwidth_size  = var.vpn_gateway_bandwidth
    charge_mode     = "traffic"
  }

  slave_eip {
    type            = "5_bgp"
    bandwidth_name  = "lz-vpn-slave-bw"
    bandwidth_size  = var.vpn_gateway_bandwidth
    charge_mode     = "traffic"
  }
}
