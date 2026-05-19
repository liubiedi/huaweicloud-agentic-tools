variable "home_region" {
  type        = string
  description = "Region for the spoke VPC"
}

variable "spoke_name" {
  type        = string
  description = "Name prefix for all spoke resources"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the spoke VPC"
}

variable "subnets" {
  type = list(object({
    name        = string
    cidr        = string
    zone        = string
    description = optional(string, "")
  }))
  description = "Subnets to create in the spoke VPC"
}

variable "er_instance_id" {
  type        = string
  description = "Enterprise Router instance ID to attach to"
}

variable "er_attach_subnet_cidr" {
  type        = string
  description = "CIDR for the small ER attachment subnet"
}

variable "er_attach_zone" {
  type        = string
  description = "AZ for the ER attachment subnet"
}

variable "hub_cidr" {
  type        = string
  description = "Hub VPC CIDR — default route pointing to ER"
  default     = "0.0.0.0/0"
}

variable "lts_log_group_id" {
  type        = string
  description = "LTS log group ID for VPC flow logs"
  default     = ""
}

variable "lts_log_stream_id" {
  type        = string
  description = "LTS log stream ID for VPC flow logs"
  default     = ""
}

variable "enable_security_group" {
  type        = bool
  description = "Create a baseline security group for the spoke"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to spoke resources"
  default     = {}
}
