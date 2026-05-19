variable "home_region" {
  type    = string
  default = "cn-east-3"
}

variable "master_access_key" {
  type      = string
  sensitive = true
}

variable "master_secret_key" {
  type      = string
  sensitive = true
}

variable "network_ops_account_domain" {
  type = string
}

variable "tfstate_bucket" {
  type        = string
  description = "OBS bucket holding all env state files"
}

variable "hub_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "hub_subnet_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "firewall_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "availability_zones" {
  type    = list(string)
  default = ["cn-east-3a", "cn-east-3b"]
}

variable "enable_vpn_gateway" {
  type    = bool
  default = false
}

variable "public_dns_zones" {
  type = list(object({
    name  = string
    email = optional(string, "")
  }))
  default = []
}

variable "private_dns_zones" {
  type = list(object({
    name              = string
    associated_vpc_id = string
  }))
  default = []
}
