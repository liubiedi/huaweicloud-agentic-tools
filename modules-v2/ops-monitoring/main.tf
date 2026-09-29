terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = { source = "huaweicloud/huaweicloud", version = "~> 1.87" }
  }
}

# Ops monitoring (SMN topics + CES alarms).
# Resources live in smn.tf and sibling files. Tagging is provider-level
# (default_tags) only - modules inject no tags of their own.
