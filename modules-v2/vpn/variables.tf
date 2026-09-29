# --- VPN inputs ---

variable "enterprise_project_id" {
  type        = string
  default     = "0"
  description = "Enterprise project ID for the VPN resources. '0' = default project."
}

# --- Network name-to-ID maps ---

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

# --- Gateway and connection inputs ---

variable "gateways" {
  type = list(object({
    name = string
    # Values: vpc, er
    attachment = optional(string, "er")
    # Note: VPC name is required for both VPC and ER attachments.
    vpc = optional(string, "")
    # Connection or ER access subnet name
    connect_subnet = optional(string, "")
    # Advertised CIDRs for VPC attachment
    local_subnets = optional(list(string), [])
    # Values: public (2 EIPs), private
    network_type = optional(string, "public")
    # Values: active-active, active-standby
    ha_mode = optional(string, "active-standby")
    # Note: Blank uses the API default flavor.
    flavor = optional(string, "")
    # Note: Empty selects two valid zones for the gateway flavor and attachment.
    azs = optional(list(string), [])
    asn = optional(number, 64512)
    # Public EIP bandwidth in Mbit/s
    bandwidth_size = optional(number, 100)
    # Note: EIP billing changes can replace resources; change live billing in the console.
    eip_charge_mode = optional(string, "bandwidth")

    # ER route tables
    # Note: Blank skips routing; association receives traffic and propagation publishes learned routes.
    er_association_route_table = optional(string, "")
    er_propagation_route_table = optional(string, "")
  }))
  default     = []
  description = "S2C VPN gateways. network_type=public creates two EIPs (eip1/eip2) at bandwidth_size."
}

# --- On-premises route propagation ---

variable "customer_gateways" {
  type = list(object({
    name = string
    ip   = string
    asn  = optional(number, 65000)
    # Values: static, bgp
    route_mode = optional(string, "bgp")
  }))
  default     = []
  description = "On-premises customer gateways."
}

variable "connections" {
  type = list(object({
    name = string
    # VPN gateway name
    gateway = string
    # Customer gateway name
    customer_gateway = string
    # Values: policy, static, bgp
    vpn_type     = optional(string, "bgp")
    peer_subnets = optional(list(string), [])
    # Values: master (eip1), slave (eip2)
    ha_role = optional(string, "master")
    psk     = string
  }))
  default     = []
  description = "IPsec connections binding a gateway to a customer gateway. gateway_ip is the gateway EIP for the ha_role (master=eip1, slave=eip2)."
}
