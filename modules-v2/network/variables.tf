# Module 3 - network planning
#
# Single module with two halves (hub + spoke) controlled by enable flags.
# Env calls it once with enable_hub=true (in network-hub account) and N times
# with enable_spoke=true (per spoke account).

variable "environment" {
  type    = string
  default = "shared"
}
variable "tags" {
  type    = map(string)
  default = {}
}

# ---- Section toggles ----

variable "enable_hub" {
  type    = bool
  default = false
}
variable "enable_spoke" {
  type    = bool
  default = false
}

# ---- Hub inputs ----

# Recommended hub CIDR sizing (documentation):
#   - vpc-dmz       /20 minimum (NAT + ELB + per-AZ subnets)
#   - vpc-access    /23 minimum (DC/VPN gateway subnets)
#   - vpc-shared    /22 minimum (shared services future expansion)
#   - vpc-inspection /24 reserved (not created; CFW operates without a VPC)

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

# ---- Explicit resource names (surfaced in the Excel M3 sheet) ----
# Every named hub singleton takes its name from these. Defaults preserve the
# historical lz-hub-* literals so an unset value is non-breaking.

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

# ---- Enterprise Router ----

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

# ---- ER attachments + routing (explicit, attachment-centric) ----
# attachment_type discriminates how attachment/next_hop names resolve to an
# attachment_id: vpc -> er_attachments[name]; cfw -> CFW ER-mode attachment.
# (Spokes self-wire their own associations/propagations - see spoke.tf.)

variable "er_attachments" {
  type = list(object({
    name           = string
    vpc            = string                # hub VPC name
    subnet         = optional(string, "")  # subnet carrying the attachment; blank = VPC's first subnet
    auto_add_route = optional(bool, false) # auto_create_vpc_routes
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

# ER routing is fully AUTO-wired (no per-row tables):
#   - every hub + spoke VPC attachment associates to inbound_route_table and
#     propagates into outbound_route_table;
#   - the CFW ER-mode attachment associates to outbound_route_table;
#   - static route inbound 0.0.0.0/0 -> CFW;
#   - static route outbound 0.0.0.0/0 -> snat_vpc_attachment.
# Just define the two route table names in er_route_tables.
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
  description = "DNS server IPs (max 2) set on every hub + spoke subnet via DHCP (primary_dns/secondary_dns). Point these at the inbound DNS resolver endpoint IPs (module 09-dns) so all accounts resolve the central private zones + on-prem forwarding rules. Empty = Huawei default DNS."
  validation {
    condition     = length(var.subnet_dns) <= 2
    error_message = "subnet_dns accepts at most 2 IPs (primary + secondary)."
  }
}

# ---- VPC flow logs (hub + spoke, uniform) ----
# One LTS group + stream per VPC, both named '<vpc>-flowlog' (per-VPC groups so
# multiple spokes in one account never race on a group name), plus a
# huaweicloud_vpc_flow_log capturing ALL traffic. Aggregate to the archive
# bucket via 06_Observability LogConverge rows (SourceGroup/Stream = <vpc>-flowlog).

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

# Hub VPC default-route tables are AUTO-wired (snat_vpc_attachment +
# spoke_private_supernet): the SNAT VPC gets 0.0.0.0/0 -> its NAT gateway and
# <supernet> -> ER; every other ER-attached hub VPC gets 0.0.0.0/0 -> ER.

# Spokes self-wire their ER association/propagation against the hub route tables
# (see spoke.tf) - no cross-account attachment discovery is needed because the
# hub + spokes deploy in the same apply.

# ---- Cloud Firewall ----

variable "cfw_flavor" {
  type    = string
  default = "standard"
  validation {
    condition     = contains(["standard", "professional"], var.cfw_flavor)
    error_message = "cfw_flavor must be 'standard' or 'professional'."
  }
}

# IPS attack defense on the hub firewall. null (the default) = the setting is
# NOT managed by Terraform and stays console-controlled.
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

# CFW billing - the only hub resource with a billing choice (all others are
# pay-per-use). "subscription" requires cfw_period_unit/cfw_period; auto_renew
# applies only to subscription. The module maps these to the provider's
# postPaid/prePaid values.
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
    action_type = number # 0 = allow, 1 = deny
    direction   = number # 0 = inbound, 1 = outbound
    type        = number # 0 = traffic between vpc/internet, 1 = ew
    source      = object({ type = number, address = optional(string, "") })
    destination = object({ type = number, address = optional(string, "") })
    service     = object({ type = number, protocol = number, source_port = optional(string, ""), dest_port = optional(string, "") })
    order       = object({ dest_rule_id = optional(string, ""), top = optional(bool, false) })
    status      = number # 0 = disabled, 1 = enabled
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

# One LTS stream per CFW log type (traffic/flow, access, attack).
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

# Optional override: reuse a pre-existing LTS GROUP instead of creating one. The
# three streams are still created in it. Blank = hub creates the group too.
variable "cfw_lts_group_id" {
  type        = string
  default     = ""
  description = "Pre-existing LTS group ID to reuse. Blank = hub creates from cfw_lts_log_group_name."
}

# ---- EIPs (multi-instance, dedicated bandwidth each) ----
# NAT (via SNAT/DNAT) and ELBs reference an EIP by name. All EIPs pay-per-use;
# billed_by selects bandwidth vs traffic metering.

variable "eips" {
  type = list(object({
    name           = string
    type           = optional(string, "5_bgp")
    billed_by      = optional(string, "bandwidth") # bandwidth | traffic
    bandwidth_size = optional(number, 100)
    description    = optional(string, "")
  }))
  default     = []
  description = "Elastic IPs. SNAT/DNAT and ELBs reference one by name."
}

# ---- NAT gateways (public, multi-instance) ----

variable "nat_gateways" {
  type = list(object({
    name   = string
    spec   = optional(string, "Small") # Small | Medium | Large | Extra-large
    vpc    = string                    # hub VPC name
    subnet = optional(string, "")      # subnet name; blank = VPC's first subnet
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
    nat_name    = optional(string, "") # NAT gateway name; blank = sole NAT
    cidr        = string
    eip         = string # EIP name (from var.eips)
    description = optional(string, "")
  }))
  default = []
}

variable "dnat_rules" {
  type = list(object({
    nat_name      = optional(string, "") # NAT gateway name; blank = sole NAT
    eip           = string               # EIP name (from var.eips)
    external_port = number
    internal_ip   = string
    internal_port = number
    protocol      = string
    description   = optional(string, "")
  }))
  default     = []
  description = "DNAT rules - named EIP -> internal target for public ingress."
}

# ---- ELBs (dedicated, IPv4, multi-instance) ----

variable "elbs" {
  type = list(object({
    name            = string
    azs             = optional(list(string), [])
    vpc             = string
    frontend_subnet = optional(string, "")  # VIP subnet name; blank = VPC's first subnet
    backend_subnet  = optional(string, "")  # backend member subnet name
    ip_as_backend   = optional(bool, false) # cross_vpc_backend
    eip             = optional(string, "")  # EIP name for public access; blank = internal
  }))
  default     = []
  description = "Hub dedicated (IPv4) load balancers, elastic spec (no fixed flavor). Listeners/pools reference one by loadbalancer_name."
}

variable "elb_listeners" {
  type = list(object({
    loadbalancer_name = optional(string, "") # ELB name; blank = sole ELB
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
    loadbalancer_name = optional(string, "") # ELB name; blank = sole ELB
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

# ---- RAM (cross-account share) ----

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

# ---- Spoke inputs (per-call) ----

variable "spoke_vpc_name" {
  type    = string
  default = ""
}
variable "spoke_vpc_cidr" {
  type    = string
  default = ""
}

# Explicit spoke resource names. Blank = derive from spoke_vpc_name (historical
# behaviour), so unset values are non-breaking.
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
    tags = optional(map(string), {}) # per-subnet tags (no Global default tags on spokes)
  }))
  default     = []
  description = "Spoke subnets (AZ not pinned). The FIRST subnet carries the spoke ER attachment."
}

variable "spoke_vpc_tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the spoke VPC + ER attachment. The spoke provider also carries default_tags (required - the enforced require_mandatory_tags SCP denies untagged creates); these per-row tags override every overlapping key, so they win whenever the row defines the full mandatory set."
}

# Spoke ER self-wiring (hub + spokes deploy in one apply). The hub passes its
# route-table id map; the spoke auto-associates to inbound_route_table and
# auto-propagates into outbound_route_table (the same two vars the hub uses).
variable "hub_route_table_ids" {
  type        = map(string)
  default     = {}
  description = "Hub ER route table name -> id (from the hub module's route_table_ids output)."
}

# Spoke VPC default route is auto-wired: 0.0.0.0/0 -> hub ER (see spoke.tf).

variable "spoke_er_id" {
  type        = string
  default     = ""
  description = "Hub ER ID (from hub outputs); spoke attaches to this."
}


# ---- Optional / deferred features (default disabled) ----

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

# Detailed config for the gated features lives in the respective *.tf files
# (dns.tf, waf.tf, etc. - extend per modules-day1-resources.md).
