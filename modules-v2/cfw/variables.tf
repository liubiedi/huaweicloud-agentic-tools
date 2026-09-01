# ---- Firewall + protected-object IDs (resolved by the env from 05-network state) ----

variable "fw_instance_id" {
  type        = string
  description = "Hub CFW instance ID (05-network cfw_id). Required by domain name groups."
}

variable "internet_object_id" {
  type        = string
  default     = ""
  description = "Protected-object ID for the internet border (north-south, protect_objects type=0)."
}

variable "vpc_object_id" {
  type        = string
  default     = ""
  description = "Protected-object ID for the VPC border (east-west, protect_objects type=1). Blank when the CFW has no east-west object."
}

# ---- Attack defense (internet protected object) ----

variable "enterprise_project_id" {
  type        = string
  default     = "0"
  description = "Enterprise project of the firewall. Scopes the advanced-IPS-rules data source and the reverse-shell rule assertions; a firewall in a non-default EP returns no advanced IPS rules under the default '0'."
}

variable "enable_anti_virus" {
  type        = bool
  default     = false
  description = "Antivirus on the internet border: all protocols (HTTP/SMTP/POP3/IMAP4/FTP/SMB/MAC), action block."
}

variable "enable_reverse_shell_defense" {
  type        = bool
  default     = false
  description = "Set every reverse-shell advanced IPS rule on the internet border to block+enabled (action-style; re-apply reasserts)."
}

# ---- Object groups ----

variable "address_groups" {
  type = list(object({
    name         = string
    border       = optional(string, "internet") # internet | vpc
    address_type = optional(string, "ipv4")     # ipv4 | ipv6
    members      = optional(list(string), [])   # IPs / CIDRs / ranges
    description  = optional(string, "")
  }))
  default     = []
  description = "User-defined IP address groups (+ members)."
}

variable "domain_groups" {
  type = list(object({
    name        = string
    border      = optional(string, "internet")    # internet | vpc
    type        = optional(string, "application") # application | network
    domains     = optional(list(string), [])
    description = optional(string, "")
  }))
  default     = []
  description = "Domain name groups (application or network type)."
}

variable "service_groups" {
  type = list(object({
    name        = string
    border      = optional(string, "internet")
    members     = optional(list(string), []) # 'protocol/srcport/dstport' entries
    description = optional(string, "")
  }))
  default     = []
  description = "User-defined service groups (+ members)."
}

# ---- Rules ----

variable "acl_rules" {
  type = list(object({
    name        = string
    kind        = string                    # eip | nat | vpc
    action      = optional(string, "allow") # allow | deny
    source      = optional(list(string), ["any"])
    destination = optional(list(string), ["any"])
    service     = optional(list(string), ["any"])
    status      = optional(string, "enable") # enable | disable
    direction   = optional(string, "")       # inbound | outbound; internet border only ("" = nat->outbound, eip->inbound)
    description = optional(string, "")
  }))
  default     = []
  description = "CFW ACL rules. Appended at the bottom (sequence bottom=1)."
}

variable "black_white_lists" {
  type = list(object({
    name         = optional(string, "")
    border       = optional(string, "internet") # internet | vpc
    list_type    = string                       # blacklist | whitelist
    direction    = optional(string, "source")   # source | destination
    protocol     = optional(string, "any")      # tcp | udp | icmp | icmpv6 | any
    address_type = optional(string, "ipv4")     # ipv4 | ipv6 | domain
    address      = string
    port         = optional(string, "")
    description  = optional(string, "")
  }))
  default     = []
  description = "CFW black / white list entries."
}

variable "alarm_topic_name" {
  type        = string
  default     = ""
  description = "SMN topic NAME (in the CFW account) that receives firewall alarm notifications. Required when any enable_*_alarm toggle is on."
}

variable "enable_attack_alarm" {
  type        = bool
  default     = false
  description = "Notify the alarm topic on CRITICAL/HIGH attack detections (all day)."
}

variable "enable_traffic_alarm" {
  type        = bool
  default     = false
  description = "Notify the alarm topic when firewall bandwidth utilisation crosses 80% (all day)."
}

variable "enable_eip_unprotected_alarm" {
  type        = bool
  default     = false
  description = "Notify the alarm topic when an EIP exists that the firewall does not protect."
}

variable "enable_threat_intel_alarm" {
  type        = bool
  default     = false
  description = "Notify the alarm topic on CRITICAL/HIGH threat-intelligence hits (all day)."
}
