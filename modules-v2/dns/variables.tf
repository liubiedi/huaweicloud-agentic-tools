variable "enterprise_project_id" {
  type        = string
  default     = "0"
  description = "Enterprise project ID for the DNS zones. '0' = default project."
}

# ---- Cross-resource resolution maps (provided by the env from prior-env state) ----
# The module takes name->ID maps and resolves the sheet's name references itself,
# so the env stays a thin passthrough of the 05-network remote state.

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

# ---- Zones + records ----

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
    name        = string
    vpcs        = list(string) # VPC NAMES (keys of var.vpc_ids); first = primary router, rest associated
    ttl         = optional(number, 300)
    recursive   = optional(bool, false) # true = proxy_pattern RECURSIVE (unmatched subdomains fall through to public); false = AUTHORITY
    description = optional(string, "")
  }))
  default     = []
  description = "Private DNS zones. vpcs[0] is the zone's primary router; vpcs[1:] are attached via dns_private_zone_associate. recursive=true sets proxy_pattern=RECURSIVE so names not in the zone resolve on the internet."
}

variable "recordsets" {
  type = list(object({
    zone        = string # FK -> public_zones[].name or private_zones[].name
    name        = string
    type        = string
    records     = list(string)
    ttl         = optional(number, 300)
    description = optional(string, "")
  }))
  default     = []
  description = "Record sets inside the zones above. zone references a zone by name."
}

# ---- Hybrid resolver ----

variable "resolver_endpoints" {
  type = list(object({
    name      = string
    direction = string                     # inbound | outbound
    vpc       = string                     # VPC NAME hosting the endpoint subnets
    subnets   = list(string)               # subnet names within vpc (>=1). Huawei needs >=2 resolver IPs: use >=2 subnets, or 1 subnet + >=2 ips
    ips       = optional(list(string), []) # optional fixed IPs, one per subnet (same order)
  }))
  default     = []
  description = "DNS resolver endpoints. direction=inbound lets on-prem query private zones; direction=outbound feeds resolver_rules."
}

variable "resolver_rules" {
  type = list(object({
    name        = string
    endpoint    = string       # FK -> resolver_endpoints[].name (must be outbound)
    domain_name = string       # domain to forward, trailing dot
    target_ips  = list(string) # on-prem / external DNS server IPs
    vpcs        = list(string) # VPC NAMES to associate the rule with
  }))
  default     = []
  description = "Outbound forwarding rules. Each rule forwards queries for domain_name to target_ips, and is associated to vpcs."
}

variable "access_logs" {
  type = list(object({
    name       = string
    lts_group  = string       # LTS log group NAME (resolved via data source)
    lts_stream = string       # LTS log stream NAME (resolved via data source)
    vpcs       = list(string) # VPC NAMES whose resolver queries are logged
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
