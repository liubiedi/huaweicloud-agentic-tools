# --- Network inputs ---

variable "environment" {
  type    = string
  default = "shared"
}
variable "tags" {
  type    = map(string)
  default = {}
}

# --- Feature switches ---

variable "enable_hub" {
  type    = bool
  default = false
}
variable "enable_spoke" {
  type    = bool
  default = false
}

# --- Hub address ranges ---

variable "hub_vpcs" {
  type = map(object({
    cidr = string
    subnets = list(object({
      name = string
      cidr = string
    }))
  }))
  description = "Hub VPCs to create. Keys: vpc-dmz, vpc-access, vpc-shared. Subnet AZ is not pinned (Huawei auto-places)."
  default     = {}
}

variable "enterprise_project_id" {
  type        = string
  default     = "0"
  description = "Enterprise project ID assigned to every EPS-capable hub resource (ER, CFW, NAT, ELB, EIP, LTS). '0' = default project."
}

variable "inspection_cidr_reservation" {
  type        = string
  default     = "10.0.99.0/24"
  description = "CIDR CFW consumes for its ER-mode inspection attachment. Must NOT overlap any VPC CIDR."
}

variable "east_west_firewall_mode" {
  type        = string
  default     = "er"
  description = "CFW east-west deployment mode. 'er' = CFW gets its own ER attachment; traffic steered via ER route tables."
}

variable "spoke_private_supernet" {
  type        = string
  default     = ""
  description = "Supernet covering all spoke + hub private CIDRs. The SNAT VPC auto-gets a <supernet> -> ER route (return path to spokes; more specific than its 0.0.0.0/0 -> NAT default). Blank = no return route."
}

# --- Hub resource names ---

variable "er_name" {
  type        = string
  default     = "lz-hub-er"
  description = "Name of the hub Enterprise Router."
}
variable "er_flow_log_name" {
  type        = string
  default     = "lz-hub-er-flow-log"
  description = "Name of the hub ER flow log."
}
variable "cfw_name" {
  type        = string
  default     = "lz-hub-cfw"
  description = "Name of the hub Cloud Firewall."
}
variable "er_share_name" {
  type        = string
  default     = "lz-hub-er-share"
  description = "Name of the RAM resource share for the ER attachment."
}

# --- Enterprise Router inputs ---

variable "er_asn" {
  type    = number
  default = 64512
}
variable "er_availability_zones" {
  type    = list(string)
  default = ["az1", "az2"]
}
variable "er_auto_accept_shared_attachments" {
  type    = bool
  default = true
}

# --- ER attachment inputs ---

variable "er_attachments" {
  type = list(object({
    name = string
    # Hub VPC name
    vpc = string
    # Note: Blank selects the first VPC subnet.
    subnet = optional(string, "")
    # Automatic VPC routes
    auto_add_route = optional(bool, false)
    description    = optional(string, "")
  }))
  default     = []
  description = "Hub ER VPC attachments. Associations/propagations/static routes reference these by name."
}

variable "er_route_tables" {
  type = list(object({
    name        = string
    description = optional(string, "")
  }))
  default     = []
  description = "Custom ER route tables. ER default association/propagation is disabled, so these + associations/propagations/static routes drive all routing."
}

# --- Inspection routing inputs ---
variable "inbound_route_table" {
  type        = string
  default     = "er-inbound"
  description = "ER route table all VPC attachments associate to, with an auto static route 0.0.0.0/0 -> CFW. Blank = no auto-association/inbound-route."
}
variable "outbound_route_table" {
  type        = string
  default     = "er-outbound"
  description = "ER route table all VPC attachments propagate into, the CFW attachment associates to, with an auto static route 0.0.0.0/0 -> snat_vpc_attachment. Blank = none."
}
variable "snat_vpc_attachment" {
  type        = string
  default     = ""
  description = "ER VPC attachment name (from er_attachments) hosting the egress NAT gateway. The outbound RT's auto static route 0.0.0.0/0 points here. Blank = no outbound default route."
}

variable "cfw_default_route_tables" {
  type        = list(string)
  default     = []
  description = "Additional ER route tables (names from er_route_tables) that get an auto static route 0.0.0.0/0 -> CFW, like the inbound RT. Used by dedicated hybrid tables (VPN/DC attachments) so on-prem traffic is CFW-inspected. inbound_route_table is excluded automatically (it already has the route)."
}

variable "subnet_dns" {
  type        = list(string)
  default     = []
  description = "DNS server IPs (max 2) set on every hub + spoke subnet via DHCP (primary_dns/secondary_dns). Point these at the inbound DNS resolver endpoint IPs (08-network-dns) so all accounts resolve the central private zones + on-prem forwarding rules. Empty = Huawei default DNS."
  validation {
    condition     = length(var.subnet_dns) <= 2
    error_message = "subnet_dns accepts at most 2 IPs (primary + secondary)."
  }
}

# --- VPC flow-log inputs ---

variable "enable_vpc_flow_logs" {
  type        = bool
  default     = false
  description = "Create an LTS group/stream + flow log (traffic_type=all) for every hub and spoke VPC."
}

variable "flow_log_retention_days" {
  type        = number
  default     = 90
  description = "Hot LTS retention (days) of the per-VPC '<vpc>-flowlog' groups/streams."
}

# --- Firewall inputs ---

variable "cfw_flavor" {
  type    = string
  default = "standard"
  validation {
    condition     = contains(["standard", "professional"], var.cfw_flavor)
    error_message = "cfw_flavor must be 'standard' or 'professional'."
  }
}

# --- Firewall IPS settings ---
# Note: null leaves settings under console management.
variable "cfw_ips_protection_mode" {
  type    = number
  default = null
  validation {
    condition     = var.cfw_ips_protection_mode == null || contains([0, 1, 2, 3], var.cfw_ips_protection_mode)
    error_message = "cfw_ips_protection_mode must be 0 (observe), 1 (strict), 2 (medium) or 3 (loose)."
  }
}

variable "cfw_ips_patch_enabled" {
  type    = bool
  default = null
}

# --- Firewall billing inputs ---
# Note: Subscription requires a period and unit; auto-renew applies only to subscription.
variable "cfw_charging_mode" {
  type        = string
  default     = "pay-per-use"
  description = "pay-per-use | subscription."
  validation {
    condition     = contains(["pay-per-use", "subscription"], var.cfw_charging_mode)
    error_message = "cfw_charging_mode must be 'pay-per-use' or 'subscription'."
  }
}
variable "cfw_period_unit" {
  type        = string
  default     = "month"
  description = "Subscription period unit (month | year). Ignored when pay-per-use."
}
variable "cfw_period" {
  type        = number
  default     = 1
  description = "Subscription period count. Ignored when pay-per-use."
}
variable "cfw_auto_renew" {
  type        = bool
  default     = false
  description = "Auto-renew the subscription CFW. Ignored when pay-per-use."
}

variable "cfw_acl_rules" {
  type = list(object({
    name        = string
    description = optional(string, "")
    # Values: 0 allow, 1 deny
    action_type = number
    # Values: 0 inbound, 1 outbound
    direction = number
    # Values: 0 internet, 1 east-west
    type        = number
    source      = object({ type = number, address = optional(string, "") })
    destination = object({ type = number, address = optional(string, "") })
    service     = object({ type = number, protocol = number, source_port = optional(string, ""), dest_port = optional(string, "") })
    order       = object({ dest_rule_id = optional(string, ""), top = optional(bool, false) })
    # Values: 0 disabled, 1 enabled
    status = number
  }))
  default = []
}

variable "cfw_address_groups" {
  type = list(object({
    name        = string
    description = optional(string, "")
    members     = list(string)
  }))
  default = []
}

variable "cfw_service_groups" {
  type = list(object({
    name        = string
    description = optional(string, "")
    members     = list(object({ protocol = number, source_port = string, dest_port = string }))
  }))
  default = []
}

variable "cfw_lts_log_enable" {
  type        = bool
  default     = true
  description = "Enable streaming CFW logs to LTS. The hub creates the log group + stream named below."
}

variable "cfw_lts_log_group_name" {
  type        = string
  default     = "lz-hub-cfw"
  description = "Name of the LTS log group the hub creates for CFW logs (when cfw_lts_log_enable=true)."
}

# --- Firewall log streams ---
variable "cfw_lts_traffic_stream_name" {
  type        = string
  default     = "cfw-traffic"
  description = "LTS stream name for CFW traffic/flow logs (also used for the ER attachment flow log)."
}
variable "cfw_lts_access_stream_name" {
  type        = string
  default     = "cfw-access"
  description = "LTS stream name for CFW access logs."
}
variable "cfw_lts_attack_stream_name" {
  type        = string
  default     = "cfw-attack"
  description = "LTS stream name for CFW attack logs."
}

# --- Existing firewall log group ---
# Note: A supplied group is reused; the three streams are still created.
variable "cfw_lts_group_id" {
  type        = string
  default     = ""
  description = "Pre-existing LTS group ID to reuse. Blank = hub creates from cfw_lts_log_group_name."
}

# --- Public IP inputs ---

variable "eips" {
  type = list(object({
    name = string
    type = optional(string, "5_bgp")
    # Values: bandwidth, traffic
    billed_by      = optional(string, "bandwidth")
    bandwidth_size = optional(number, 100)
    description    = optional(string, "")
  }))
  default     = []
  description = "Elastic IPs. SNAT/DNAT and ELBs reference one by name."
}

# --- NAT gateway inputs ---

variable "nat_gateways" {
  type = list(object({
    name = string
    # Values: Small, Medium, Large, Extra-large
    spec = optional(string, "Small")
    # Hub VPC name
    vpc = string
    # Note: Blank selects the first VPC subnet.
    subnet = optional(string, "")
  }))
  default     = []
  description = "Hub public NAT gateways. SNAT/DNAT rules reference one by name and supply the EIP."
  validation {
    condition     = alltrue([for n in var.nat_gateways : contains(["Small", "Medium", "Large", "Extra-large"], n.spec)])
    error_message = "Each nat_gateways.spec must be Small/Medium/Large/Extra-large."
  }
}

variable "snat_rules" {
  type = list(object({
    # Note: Blank selects the sole NAT gateway.
    nat_name = optional(string, "")
    cidr     = string
    # Public IP name
    eip         = string
    description = optional(string, "")
  }))
  default = []
}

variable "dnat_rules" {
  type = list(object({
    # Note: Blank selects the sole NAT gateway.
    nat_name = optional(string, "")
    # Public IP name
    eip           = string
    external_port = number
    internal_ip   = string
    internal_port = number
    protocol      = string
    description   = optional(string, "")
  }))
  default     = []
  description = "DNAT rules - named EIP -> internal target for public ingress."
}

# --- Load balancer inputs ---

variable "elbs" {
  type = list(object({
    name = string
    azs  = optional(list(string), [])
    vpc  = string
    # Note: Blank selects the first VPC subnet for the VIP.
    frontend_subnet = optional(string, "")
    # Backend subnet name
    backend_subnet = optional(string, "")
    # Cross-VPC backends
    ip_as_backend = optional(bool, false)
    # Note: Blank creates an internal load balancer.
    eip = optional(string, "")
  }))
  default     = []
  description = "Hub dedicated (IPv4) load balancers, elastic spec (no fixed flavor). Listeners/pools reference one by loadbalancer_name."
}

variable "elb_listeners" {
  type = list(object({
    # Note: Blank selects the sole load balancer.
    loadbalancer_name = optional(string, "")
    name              = string
    protocol          = string
    protocol_port     = number
    default_pool_name = string
    certificate_arn   = optional(string, "")
  }))
  default = []
}

variable "elb_pools" {
  type = list(object({
    # Note: Blank selects the sole load balancer.
    loadbalancer_name = optional(string, "")
    name              = string
    protocol          = string
    lb_method         = string
    description       = optional(string, "")
  }))
  default = []
}

variable "elb_lts_group_id" {
  type    = string
  default = ""
}
variable "elb_lts_stream_id" {
  type    = string
  default = ""
}

# --- Resource sharing inputs ---

variable "ram_share_principals" {
  type        = list(string)
  default     = []
  description = "Account IDs or OU IDs to share the ER attachment with."
}

variable "er_share_owner_account_id" {
  type        = string
  default     = ""
  description = "Domain (account) ID that owns the hub ER - i.e. the hub member account. Used to build the RAM resource URN (er:<region>:<account-id>:enterpriseRouter:<er-id>). Required when ram_share_principals is non-empty; supplied by the env from the foundation accounts map."
}

# --- Spoke VPC inputs ---

variable "spoke_vpc_name" {
  type    = string
  default = ""
}
variable "spoke_vpc_cidr" {
  type    = string
  default = ""
}

# --- Spoke resource names ---
variable "spoke_er_attachment_name" {
  type        = string
  default     = ""
  description = "Spoke ER VPC attachment name. Blank = att-<spoke_vpc_name>."
}
variable "spoke_er_attach_subnet" {
  type        = string
  default     = ""
  description = "Subnet (name) the spoke ER attachment lands on. Blank = the VPC's first subnet."
}
variable "spoke_auto_add_route" {
  type        = bool
  default     = false
  description = "TRUE = ER auto-creates the spoke VPC-side route back to the ER (auto_create_vpc_routes)."
}
variable "spoke_er_attach_enabled" {
  type        = bool
  default     = true
  description = "FALSE = isolated spoke: VPC/subnets/SG/flow log are created, but NO ER attachment, 0/0->ER route, association or propagation (unreachable from hub/spokes). Driven by the absence of a SpokeERAttachments row."
}
variable "spoke_secgroup_name" {
  type        = string
  default     = ""
  description = "Spoke baseline security group name. Blank = <spoke_vpc_name>-baseline."
}

variable "spoke_subnets" {
  type = list(object({
    name = string
    cidr = string
    # Subnet resource tags
    tags = optional(map(string), {})
  }))
  default     = []
  description = "Spoke subnets (AZ not pinned). The FIRST subnet carries the spoke ER attachment."
}

variable "spoke_vpc_tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the spoke VPC + ER attachment. The spoke provider also carries default_tags (required - the enforced require_mandatory_tags SCP denies untagged creates); these per-row tags override every overlapping key, so they win whenever the row defines the full mandatory set."
}

# --- Spoke ER routing ---
variable "hub_route_table_ids" {
  type        = map(string)
  default     = {}
  description = "Hub ER route table name -> id (from the hub module's route_table_ids output)."
}

# --- Spoke default route ---

variable "spoke_er_id" {
  type        = string
  default     = ""
  description = "Hub ER ID (from hub outputs); spoke attaches to this."
}

# --- Currently unused feature inputs ---
# Note: These inputs enable nothing in this module; no resource reads them.

variable "enable_dns" {
  type    = bool
  default = false
}
variable "enable_waf" {
  type    = bool
  default = false
}
variable "enable_hybrid_dns" {
  type    = bool
  default = false
}
variable "enable_dc" {
  type    = bool
  default = false
}
variable "enable_vpn" {
  type    = bool
  default = false
}
variable "enable_client_vpn" {
  type    = bool
  default = false
}
variable "enable_traffic_mirror" {
  type    = bool
  default = false
}

