terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = { source = "huaweicloud/huaweicloud", version = "~> 1.87" }
    time        = { source = "hashicorp/time", version = ">= 0.9" }
  }
}
