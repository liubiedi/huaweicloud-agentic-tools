# --- Provider requirements ---

terraform {
  required_version = ">= 1.6.3"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.87"
      # Provider aliases
      # Note: huaweicloud deploys resources; huaweicloud.owner manages hub ER routing.
      configuration_aliases = [huaweicloud.owner]
    }
    time = { source = "hashicorp/time", version = ">= 0.9" }
  }
}

# --- Network configuration ---

locals {
  hub_enabled   = var.enable_hub
  spoke_enabled = var.enable_spoke

  # Enabled hub VPCs
  effective_hub_vpcs = local.hub_enabled ? var.hub_vpcs : {}

  # Hub subnet mapping
  hub_subnets_flat = local.hub_enabled ? flatten([
    for vpc_name, vpc in local.effective_hub_vpcs : [
      for subnet in vpc.subnets : merge(subnet, { vpc_name = vpc_name, key = "${vpc_name}__${subnet.name}" })
    ]
  ]) : []

  # Spoke attachment subnet selection
  spoke_er_attach_subnet = local.spoke_enabled ? (
    var.spoke_er_attach_subnet != "" ? var.spoke_er_attach_subnet : var.spoke_subnets[0].name
  ) : null
}

check "spoke_inputs_provided" {
  assert {
    condition     = !var.enable_spoke || (var.spoke_vpc_name != "" && var.spoke_vpc_cidr != "" && length(var.spoke_subnets) > 0)
    error_message = "enable_spoke = true requires spoke_vpc_name, spoke_vpc_cidr, and at least one entry in spoke_subnets."
  }
}

