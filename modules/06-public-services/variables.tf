variable "home_region" {
  type        = string
  description = "Deployment region"
}

variable "vpc_id" {
  type        = string
  description = "Hub or shared VPC ID for public-service resources"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for ELB and WAF dedicated instances"
}

variable "elb_name" {
  type        = string
  description = "Name of the shared ELB instance"
  default     = "lz-shared-elb"
}

variable "elb_availability_zones" {
  type        = list(string)
  description = "AZs for ELB"
}

variable "enable_waf" {
  type        = bool
  description = "Deploy a WAF dedicated instance"
  default     = true
}

variable "waf_name" {
  type        = string
  description = "WAF dedicated instance name"
  default     = "lz-waf"
}

variable "waf_specification_code" {
  type        = string
  description = "WAF specification code"
  default     = "waf.instance.professional"
}

variable "public_dns_zones" {
  type = list(object({
    name        = string
    description = optional(string, "")
    email       = optional(string, "")
  }))
  description = "Public DNS zones to create"
  default     = []
}

variable "private_dns_zones" {
  type = list(object({
    name        = string
    associated_vpc_id = string
    description = optional(string, "")
  }))
  description = "Private DNS zones associated with VPCs"
  default     = []
}

variable "enable_elb_access_log" {
  type        = bool
  description = "Enable ELB access logging to LTS"
  default     = true
}

variable "lts_log_group_id" {
  type        = string
  description = "LTS log group ID for ELB access logs"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags for public service resources"
  default     = {}
}
