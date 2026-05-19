terraform {
  required_version = ">= 1.6.3"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.87"
    }
  }

  # Local backend for bootstrap — state is committed to the repo for this env only
  # After OBS bucket is created, migrate to S3 backend for subsequent envs
  backend "local" {
    path = "terraform.tfstate"
  }
}
