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

provider "huaweicloud" {
  region     = var.home_region
  access_key = var.master_access_key
  secret_key = var.master_secret_key
}

# IMPORTANT: enforce_mode defaults to false.
# Enable only after:
#   1. All spoke VPCs have VPC endpoints for OBS deployed
#   2. SCPs have been tested in sandbox with enforce_mode = false for ≥ 1 week
#   3. Security team has signed off

module "data_perimeter" {
  source = "../../modules/13-data-perimeter"

  providers = {
    huaweicloud = huaweicloud
  }

  home_region    = var.home_region
  root_id        = data.terraform_remote_state.foundation.outputs.root_id
  enforce_mode   = var.enforce_mode

  deny_services = var.deny_services
}
