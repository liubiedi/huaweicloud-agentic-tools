# ---- Hub outputs ----

output "er_id" {
  description = "Hub ER instance ID. Spokes use this as spoke_er_id."
  value       = local.hub_enabled ? huaweicloud_er_instance.hub[0].id : null
}

# er_urn removed - huaweicloud_er_instance does not export `urn` attribute.
# RAM share builds the resource URN string manually from id + region + account.

output "er_route_table_ids" {
  description = "Map of route table name -> ID"
  value       = local.hub_enabled ? { for k, v in huaweicloud_er_route_table.rt : k => v.id } : {}
}

output "hub_vpc_ids" {
  description = "Map of hub VPC name -> ID"
  value       = { for k, v in huaweicloud_vpc.hub : k => v.id }
}

output "hub_subnet_ids" {
  description = "Map of hub subnet key (vpc__subnet) -> subnet ID"
  value       = { for k, v in huaweicloud_vpc_subnet.hub : k => v.id }
}

output "inspection_cidr_reservation" {
  description = "Reserved CIDR for inspection plane (not created - overlap detection only)"
  value       = local.hub_enabled ? var.inspection_cidr_reservation : null
}

output "nat_gateway_ids" {
  description = "Hub NAT gateway IDs, keyed by NAT name"
  value       = { for k, v in huaweicloud_natv3_gateway.hub : k => v.id }
}

output "eip_ids" {
  description = "EIP IDs, keyed by EIP name"
  value       = { for k, v in huaweicloud_vpc_eip.this : k => v.id }
}

output "eip_addresses" {
  description = "EIP public IPs, keyed by EIP name"
  value       = { for k, v in huaweicloud_vpc_eip.this : k => v.address }
}

output "route_table_ids" {
  description = "Hub ER route table name -> id (spokes self-wire against these)"
  value       = { for k, v in huaweicloud_er_route_table.rt : k => v.id }
}

output "cfw_id" {
  description = "CFW instance ID"
  value       = local.hub_enabled ? huaweicloud_cfw_firewall.hub[0].id : null
}

output "ingress_elb_ids" {
  description = "ELB IDs, keyed by ELB name"
  value       = { for k, v in huaweicloud_elb_loadbalancer.ingress : k => v.id }
}

output "ingress_elb_private_ips" {
  description = "ELB private VIPs (DNAT targets), keyed by ELB name"
  value       = { for k, v in huaweicloud_elb_loadbalancer.ingress : k => v.ipv4_address }
}

output "ram_share_id" {
  description = "RAM share for ER attachment (null if no principals)"
  value       = local.hub_enabled && length(var.ram_share_principals) > 0 ? huaweicloud_ram_resource_share.er_attachment[0].id : null
}

# ---- Spoke outputs ----

output "spoke_vpc_id" {
  description = "Spoke VPC ID (only when enable_spoke = true)"
  value       = local.spoke_enabled ? huaweicloud_vpc.spoke[0].id : null
}

output "spoke_subnet_ids" {
  description = "Map of spoke subnet name -> ID"
  value       = { for k, v in huaweicloud_vpc_subnet.spoke : k => v.id }
}

output "spoke_er_attachment_id" {
  description = "Spoke ER attachment ID (null for unattached/isolated spokes)"
  value       = local.spoke_enabled && var.spoke_er_attach_enabled ? huaweicloud_er_vpc_attachment.spoke[0].id : null
}

output "spoke_baseline_sg_id" {
  description = "Spoke baseline SG ID"
  value       = local.spoke_enabled ? huaweicloud_networking_secgroup.baseline[0].id : null
}
