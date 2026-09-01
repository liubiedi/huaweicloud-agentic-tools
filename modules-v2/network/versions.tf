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
