output "vpc_id" {
  value       = huaweicloud_vpc.spoke.id
  description = "Spoke VPC ID"
}

output "vpc_cidr" {
  value       = huaweicloud_vpc.spoke.cidr
  description = "Spoke VPC CIDR"
}

output "subnet_ids" {
  value       = { for k, v in huaweicloud_vpc_subnet.subnets : k => v.id }
  description = "Map of subnet name to subnet ID"
}

output "er_attachment_id" {
  value       = huaweicloud_er_vpc_attachment.spoke.id
  description = "ER VPC attachment ID"
}

output "er_attach_subnet_id" {
  value       = huaweicloud_vpc_subnet.er_attach.id
  description = "ER attachment subnet ID"
}

output "baseline_sg_id" {
  value       = var.enable_security_group ? huaweicloud_networking_secgroup.baseline[0].id : null
  description = "Baseline security group ID"
}

output "route_table_id" {
  value       = huaweicloud_vpc_route_table.spoke.id
  description = "Spoke VPC route table ID"
}
