variable "home_region" {
  type        = string
  description = "Region for the Enterprise Router and hub resources"
}

variable "er_name" {
  type        = string
  description = "Enterprise Router instance name"
  default     = "lz-er-hub"
}

variable "er_asn" {
  type        = number
  description = "BGP ASN for the Enterprise Router"
  default     = 64512
}

variable "hub_vpc_cidr" {
  type        = string
  description = "CIDR for the hub VPC (transit/inspection)"
  default     = "10.0.0.0/16"
}

variable "hub_subnet_cidr" {
  type        = string
  description = "CIDR for the ER attachment subnet in the hub VPC"
  default     = "10.0.0.0/24"
}

variable "firewall_subnet_cidr" {
  type        = string
  description = "CIDR for the Cloud Firewall subnet"
  default     = "10.0.1.0/24"
}

variable "spoke_account_ids" {
  type        = list(string)
  description = "Account IDs to share the ER with via RAM"
  default     = []
}

variable "enable_cloud_firewall" {
  type        = bool
  description = "Deploy a Cloud Firewall instance for east-west and N-S inspection"
  default     = true
}

variable "cfw_name" {
  type        = string
  description = "Cloud Firewall instance name"
  default     = "lz-cfw"
}

variable "cfw_type" {
  type        = number
  description = "CFW type: 0=standard, 1=professional"
  default     = 1
}

variable "nat_public_eip_bandwidth" {
  type        = number
  description = "Shared bandwidth in Mbit/s for NAT public EIPs"
  default     = 100
}

variable "enable_vpn_gateway" {
  type        = bool
  description = "Deploy a VPN gateway for site-to-site connectivity"
  default     = false
}

variable "vpn_gateway_bandwidth" {
  type        = number
  description = "VPN gateway bandwidth in Mbit/s"
  default     = 100
}

variable "lts_log_group_id" {
  type        = string
  description = "LTS log group ID for ER flow logs"
  default     = ""
}

variable "lts_log_stream_id" {
  type        = string
  description = "LTS log stream ID for ER flow logs"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to hub resources"
  default     = {}
}
