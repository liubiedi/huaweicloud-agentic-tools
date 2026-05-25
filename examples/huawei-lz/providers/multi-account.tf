# Provider definitions for the master (management) account.
# Aliased providers for member accounts (network_ops, logging, security_ops, ...)
# get added here as later envs need them. They use:
#
#   provider "huaweicloud" {
#     alias = "<account>"
#     region = var.home_region
#     assume_role {
#       agency_name = "OrganizationAccountAccessAgency"   # RGC creates this
#       domain_name = var.<account>_account_domain        # the member's domain name
#     }
#   }
#
# For the RGC bootstrap, only the master/default provider is needed.

provider "huaweicloud" {
  region     = var.home_region
  access_key = var.master_access_key
  secret_key = var.master_secret_key

  default_tags = {
    ManagedBy   = "terraform"
    Project     = "landing-zone"
    Environment = var.environment
  }
}
