data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket   = var.tfstate_bucket
    key      = "envs/01-foundation/terraform.tfstate"
    region   = var.home_region
    endpoints = {
      s3 = "https://obs.${var.home_region}.myhuaweicloud.com"
    }
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}

data "terraform_remote_state" "audit_logging" {
  backend = "s3"
  config = {
    bucket   = var.tfstate_bucket
    key      = "envs/03-security-audit/terraform.tfstate"
    region   = var.home_region
    endpoints = {
      s3 = "https://obs.${var.home_region}.myhuaweicloud.com"
    }
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}

provider "huaweicloud" {
  alias  = "network_ops"
  region = var.home_region

  assume_role {
    agency_name = "OrganizationAccountAccessAgency"
    domain_name = var.network_ops_account_domain
  }
}

module "network_hub" {
  source = "../../modules/04-network-hub"

  providers = {
    huaweicloud = huaweicloud.network_ops
  }

  home_region           = var.home_region
  er_name               = "lz-er-hub"
  er_asn                = 64512
  hub_vpc_cidr          = var.hub_vpc_cidr
  hub_subnet_cidr       = var.hub_subnet_cidr
  firewall_subnet_cidr  = var.firewall_subnet_cidr
  spoke_account_ids     = values(data.terraform_remote_state.foundation.outputs.member_account_ids)
  enable_cloud_firewall = true
  enable_vpn_gateway    = var.enable_vpn_gateway
  nat_public_eip_bandwidth = 100
}

module "public_services" {
  source = "../../modules/06-public-services"

  providers = {
    huaweicloud = huaweicloud.network_ops
  }

  home_region            = var.home_region
  vpc_id                 = module.network_hub.hub_vpc_id
  subnet_id              = module.network_hub.hub_vpc_id # override with correct subnet
  elb_availability_zones = var.availability_zones
  enable_waf             = true

  public_dns_zones  = var.public_dns_zones
  private_dns_zones = var.private_dns_zones
}

module "shared_resources" {
  source = "../../modules/07-shared-resources"

  providers = {
    huaweicloud = huaweicloud.network_ops
  }

  home_region = var.home_region

  kms_keys = [
    {
      alias              = "lz-shared-data-key"
      description        = "Shared KMS key for workload data encryption"
      rotation_enabled   = true
      shared_account_ids = values(data.terraform_remote_state.foundation.outputs.member_account_ids)
    }
  ]
}

provider "huaweicloud" {
  region     = var.home_region
  access_key = var.master_access_key
  secret_key = var.master_secret_key
}
