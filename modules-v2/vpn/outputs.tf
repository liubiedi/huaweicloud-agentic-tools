output "gateway_ids" {
  description = "VPN gateway NAME -> ID."
  value       = { for k, v in huaweicloud_vpn_gateway.this : k => v.id }
}

output "gateway_eips" {
  description = "VPN gateway NAME -> [active(eip1), standby(eip2)] public IPs (public gateways only)."
  value = {
    for k, v in huaweicloud_vpn_gateway.this : k => compact([
      try(v.eip1[0].ip_address, ""),
      try(v.eip2[0].ip_address, ""),
    ])
  }
}

output "er_attachment_ids" {
  description = "VPN gateway NAME -> its ER attachment ID (er-attached gateways only)."
  value = {
    for k, v in huaweicloud_vpn_gateway.this : k => v.er_attachment_id
    if v.attachment_type == "er"
  }
}

output "customer_gateway_ids" {
  description = "Customer gateway NAME -> ID."
  value       = { for k, v in huaweicloud_vpn_customer_gateway.this : k => v.id }
}

output "connection_ids" {
  description = "VPN connection NAME -> ID."
  value       = { for k, v in huaweicloud_vpn_connection.this : k => v.id }
}
