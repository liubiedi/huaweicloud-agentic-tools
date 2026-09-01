variable "enterprise_project_id" {
  type        = string
  default     = "0"
  description = "Enterprise project ID for the VPN resources. '0' = default project."
}

# ---- Cross-resource resolution (from the env, out of 05-network state) ----

variable "vpc_ids" {
  type        = map(string)
  default     = {}
  description = "VPC NAME -> ID (05-network hub+spoke). Used for gateways with attachment=vpc."
}

variable "subnet_ids" {
  type        = map(string)
  default     = {}
  description = "Subnet key '<vpc>__<subnet>' -> ID (05-network hub_subnet_ids). Used for the gateway connect_subnet (vpc attachment)."
}

variable "er_id" {
  type        = string
  default     = ""
  description = "Hub Enterprise Router ID (05-network er_id). Used for gateways with attachment=er."
}

variable "er_route_table_ids" {
  type        = map(string)
  default     = {}
  description = "Hub ER route table NAME -> ID (05-network route_table_ids). Referenced by the gateways' er_*_route_table fields and by er_static_routes."
}

# ---- Gateways / customer gateways / connections ----

variable "gateways" {
  type = list(object({
    name            = string
    attachment      = optional(string, "er")             # vpc | er
    vpc             = optional(string, "")               # VPC name: vpc attach -> vpc_id; er attach -> access_vpc_id (required for both)
    connect_subnet  = optional(string, "")               # subnet name within vpc: vpc attach -> connect_subnet; er attach -> access_subnet_id
    local_subnets   = optional(list(string), [])         # vpc attachment only: local CIDRs advertised
    network_type    = optional(string, "public")         # public (2 EIPs) | private
    ha_mode         = optional(string, "active-standby") # active-active | active-standby
    flavor          = optional(string, "")               # blank = API default (Professional1)
    azs             = optional(list(string), [])         # blank = auto-select 2 valid AZs for flavor+attachment
    asn             = optional(number, 64512)
    bandwidth_size  = optional(number, 100)         # public: Mbit/s per created EIP
    eip_charge_mode = optional(string, "bandwidth") # public: EIP billing - bandwidth | traffic (ForceNew: console-first to switch live)

    # ER routing (attachment=er only). The gateway's ER attachment associates to /
    # propagates into these hub route tables (names from er_route_table_ids).
    # Association steers traffic ARRIVING from on-prem (typically a dedicated
    # hybrid RT whose 0/0 points at the CFW); propagation publishes BGP-learned
    # on-prem routes (typically into the outbound RT). Blank = skip.
    er_association_route_table = optional(string, "")
    er_propagation_route_table = optional(string, "")
  }))
  default     = []
  description = "S2C VPN gateways. network_type=public creates two EIPs (eip1/eip2) at bandwidth_size."
}

# (On-prem routes enter ER route tables via propagation only.)

variable "customer_gateways" {
  type = list(object({
    name       = string
    ip         = string
    asn        = optional(number, 65000)
    route_mode = optional(string, "bgp") # static | bgp
  }))
  default     = []
  description = "On-premises customer gateways."
}

variable "connections" {
  type = list(object({
    name             = string
    gateway          = string                  # FK -> gateways[].name
    customer_gateway = string                  # FK -> customer_gateways[].name
    vpn_type         = optional(string, "bgp") # policy | static | bgp
    peer_subnets     = optional(list(string), [])
    ha_role          = optional(string, "master") # master (eip1) | slave (eip2)
    psk              = string
  }))
  default     = []
  description = "IPsec connections binding a gateway to a customer gateway. gateway_ip is the gateway EIP for the ha_role (master=eip1, slave=eip2)."
}
