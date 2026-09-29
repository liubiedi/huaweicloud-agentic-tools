terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = { source = "huaweicloud/huaweicloud", version = "~> 1.87" }
  }
}

# Security (SecMaster + deferred HSS/DBSS).
# Resources live in secmaster.tf, hss.tf, dbss.tf. Tagging is provider-level
# (default_tags) only - modules inject no tags of their own.
