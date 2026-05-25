terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.87"
    }
  }
  # Bootstrap uses LOCAL state — it creates the OBS bucket that later envs use
  # as a remote backend. After apply, the resulting terraform.tfstate should be
  # committed to a secure location (or migrated into the bucket it just made).
}
