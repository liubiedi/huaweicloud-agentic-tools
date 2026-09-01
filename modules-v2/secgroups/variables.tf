variable "security_groups" {
  description = "Security groups to create in this account. Default rules are deleted; every allow is an explicit sg_rules row."
  type = list(object({
    name        = string
    description = optional(string, "")
    tags        = optional(map(string), {})
  }))
  default = []
}

variable "sg_rules" {
  description = "Rules. remote: CIDR | sg:<group-name> (same account) | self. ports: '443', '5985-5986', '80,443', blank = all ports. protocol: tcp|udp|icmp|any."
  type = list(object({
    sg          = string
    direction   = string # ingress | egress
    protocol    = optional(string, "any")
    ports       = optional(string, "")
    remote      = string
    action      = optional(string, "allow")
    description = optional(string, "")
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.sg_rules : contains(["ingress", "egress"], r.direction)])
    error_message = "direction must be ingress or egress."
  }
  validation {
    condition     = alltrue([for r in var.sg_rules : contains(["allow", "deny"], coalesce(r.action, "allow"))])
    error_message = "action must be allow or deny."
  }
}
