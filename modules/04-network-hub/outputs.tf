output "hub_vpc_id" {
  value       = huaweicloud_vpc.hub.id
  description = "Hub VPC ID"
}

output "hub_vpc_cidr" {
  value       = huaweicloud_vpc.hub.cidr
  description = "Hub VPC CIDR block"
}

output "er_instance_id" {
  value       = huaweicloud_er_instance.hub.id
  description = "Enterprise Router instance ID — used by spoke modules for VPC attachment"
}

output "er_route_table_id" {
  value       = huaweicloud_er_route_table.hub.id
  description = "Hub ER route table ID"
}

output "ram_share_id" {
  value       = huaweicloud_ram_resource_share.er.id
  description = "RAM share ID for the ER instance"
}

output "cfw_firewall_id" {
  value       = var.enable_cloud_firewall ? huaweicloud_cfw_firewall.this[0].id : null
  description = "Cloud Firewall instance ID (null if not enabled)"
}

output "nat_gateway_id" {
  value       = huaweicloud_nat_gateway.hub.id
  description = "Hub NAT Gateway ID"
}

output "nat_eip_address" {
  value       = huaweicloud_vpc_eip.nat.address
  description = "Public IP address of the hub NAT gateway"
}

output "vpn_gateway_id" {
  value       = var.enable_vpn_gateway ? huaweicloud_vpn_gateway.hub[0].id : null
  description = "VPN Gateway ID (null if not enabled)"
}
