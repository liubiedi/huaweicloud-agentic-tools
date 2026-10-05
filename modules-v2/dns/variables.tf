# --- DNS inputs ---

variable "enterprise_project_id" {
  type        = string
  default     = "0"
  description = "Enterprise project ID for the DNS zones. '0' = default project."
}

# --- Network name-to-ID maps ---

variable "vpc_ids" {
  type        = map(string)
  default     = {}
  description = "VPC NAME -> VPC ID (merged hub + spoke from 05-network). Used for private-zone routers, resolver-rule associations, and access-log VPCs."
}

variable "subnet_ids" {
  type        = map(string)
  default     = {}
  description = "Subnet key '<vpc>__<subnet>' -> subnet ID (05-network hub_subnet_ids). Used to place resolver-endpoint IPs. Resolver endpoints must sit in a hub VPC (spoke subnet IDs are not exported by 05-network)."
}

# --- Zones and records ---

variable "public_zones" {
  type = list(object({
    name        = string
    email       = optional(string, "")
    ttl         = optional(number, 300)
    description = optional(string, "")
  }))
  default     = []
  description = "Public DNS zones (internet-resolvable). name ends with a trailing dot."
}

variable "private_zones" {
  type = list(object({
    name = string
    # VPC names; first is the primary association
    vpcs = list(string)
    ttl  = optional(number, 300)
    # Note: true enables public fallback; false uses authoritative resolution.
    recursive   = optional(bool, false)
    description = optional(string, "")
  }))
  default     = []
  description = "Private DNS zones. vpcs[0] is the zone's primary router; vpcs[1:] are attached via dns_private_zone_associate. recursive=true sets proxy_pattern=RECURSIVE so names not in the zone resolve on the internet."
}

variable "recordsets" {
  type = list(object({
    # Public or private zone name
    zone        = string
    name        = string
    type        = string
    records     = list(string)
    ttl         = optional(number, 300)
    description = optional(string, "")
  }))
  default     = []
  description = "Record sets inside the zones above. zone references a zone by name."
}

# --- Hybrid resolver inputs ---

variable "resolver_endpoints" {
  type = list(object({
    name = string
    # Values: inbound, outbound
    direction = string
    # Resolver VPC name
    vpc = string
    # Note: Use at least two subnets, or one subnet with at least two fixed IPs.
    subnets = list(string)
    # Optional resolver IPs in subnet order
    ips = optional(list(string), [])
  }))
  default     = []
  description = "DNS resolver endpoints. direction=inbound lets on-prem query private zones; direction=outbound feeds resolver_rules."
}

variable "resolver_rules" {
  type = list(object({
    name = string
    # Outbound resolver endpoint name
    endpoint = string
    # Forwarded domain with trailing dot
    domain_name = string
    # Upstream DNS server IPs
    target_ips = list(string)
    # Associated VPC names
    vpcs = list(string)
  }))
  default     = []
  description = "Outbound forwarding rules. Each rule forwards queries for domain_name to target_ips, and is associated to vpcs."
}

variable "access_logs" {
  type = list(object({
    name = string
    # LTS log group name
    lts_group = string
    # LTS log stream name
    lts_stream = string
    # Logged VPC names
    vpcs = list(string)
  }))
  default     = []
  description = "DNS query access logging to LTS. lts_group/lts_stream are the LTS log group / stream names the module CREATES (one group per distinct name)."
}

variable "manage_query_log_infra" {
  type        = bool
  default     = true
  description = "Create the query-log LTS group/stream here (true) or look up existing ones by name (false - the observability env owns them)."
}

variable "access_log_lts_ttl_days" {
  type        = number
  default     = 30
  description = "Retention (days) for the LTS log group(s) created for DNS query access logs."
}
