terraform {
  required_version = ">= 1.6.3"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.87"
    }
  }

  backend "s3" {
    bucket   = "lz-tfstate-prod"
    key      = "envs/04-ops-finance/terraform.tfstate"
    region   = "cn-east-3"
    endpoints = {
      s3 = "https://obs.cn-east-3.myhuaweicloud.com"
    }

    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}
