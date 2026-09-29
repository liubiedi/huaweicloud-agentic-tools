terraform {
  required_version = ">= 1.6.3"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.87"
      # huaweicloud        = the account this instance deploys into (hub OR a spoke)
      # huaweicloud.owner  = the ER OWNER (hub) - used by spoke association/propagation,
      #                      which manage the hub's route tables (cross-account).
      configuration_aliases = [huaweicloud.owner]
    }
    time = { source = "hashicorp/time", version = ">= 0.9" }
  }
}

# Network planning
#
# Locals + section toggle plumbing. Hub resources in hub.tf, spoke in spoke.tf.

locals {
  hub_enabled   = var.enable_hub
  spoke_enabled = var.enable_spoke

  # All declared hub VPCs (toggle individual VPCs via the HubVPCs Enabled column).
  effective_hub_vpcs = local.hub_enabled ? var.hub_vpcs : {}

  # Flatten hub subnets across all VPCs
  hub_subnets_flat = local.hub_enabled ? flatten([
    for vpc_name, vpc in local.effective_hub_vpcs : [
      for subnet in vpc.subnets : merge(subnet, { vpc_name = vpc_name, key = "${vpc_name}__${subnet.name}" })
    ]
  ]) : []

  # Spoke ER-attach subnet: explicit (SpokeERAttachments.Subnet) else first subnet.
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

