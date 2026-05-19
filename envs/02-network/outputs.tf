output "er_instance_id" {
  value = module.network_hub.er_instance_id
}

output "hub_vpc_id" {
  value = module.network_hub.hub_vpc_id
}

output "cfw_firewall_id" {
  value = module.network_hub.cfw_firewall_id
}

output "nat_eip_address" {
  value = module.network_hub.nat_eip_address
}

output "elb_id" {
  value = module.public_services.elb_id
}

output "waf_instance_id" {
  value = module.public_services.waf_instance_id
}

output "shared_kms_key_ids" {
  value = module.shared_resources.kms_key_ids
}
