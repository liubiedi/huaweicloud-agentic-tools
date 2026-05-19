variable "home_region" {
  type        = string
  description = "Region for RMS/Config resources"
}

variable "obs_recorder_bucket" {
  type        = string
  description = "OBS bucket name for RMS resource recorder snapshots"
}

variable "smn_topic_urn" {
  type        = string
  description = "SMN topic URN for compliance violation alerts"
  default     = ""
}

variable "aggregator_account_ids" {
  type        = list(string)
  description = "Account IDs to aggregate resource data from"
  default     = []
}

variable "conformance_packs" {
  type = list(object({
    name         = string
    template_key = string
  }))
  description = "Pre-built conformance packs to deploy"
  default = [
    {
      name         = "lz-security-baseline-l1"
      template_key = "Operational-Best-Practices-for-Huawei-Cloud-Security-L1"
    },
  ]
}

variable "custom_rules" {
  type = list(object({
    name            = string
    description     = string
    policy_name     = string
    trigger_type    = optional(string, "resource")
    period          = optional(string, "TwentyFour_Hours")
    resource_types  = optional(list(string), [])
    parameters      = optional(map(string), {})
  }))
  description = "Custom RMS policy assignments to create"
  default = [
    {
      name         = "obs-bucket-versioning-enabled"
      description  = "Checks that OBS buckets have versioning enabled"
      policy_name  = "bucket-versioning-enabled"
      resource_types = ["obs:buckets"]
    },
    {
      name         = "obs-bucket-no-public-access"
      description  = "Checks that OBS buckets block public access"
      policy_name  = "obs-bucket-not-public"
      resource_types = ["obs:buckets"]
    },
    {
      name         = "kms-rotation-enabled"
      description  = "Checks that KMS keys have rotation enabled"
      policy_name  = "kms-key-rotation-enabled"
      resource_types = ["kms:keys"]
    },
    {
      name         = "ecs-in-vpc"
      description  = "Checks that ECS instances are deployed within a VPC"
      policy_name  = "ecs-instance-in-vpc"
      resource_types = ["ecs:cloudservers"]
    },
    {
      name         = "sg-no-unrestricted-ssh"
      description  = "Checks that no security group allows unrestricted SSH (port 22)"
      policy_name  = "restricted-ssh"
      resource_types = ["vpc:securityGroups"]
    },
  ]
}

variable "enterprise_project_id" {
  type        = string
  description = "Enterprise project ID"
  default     = "0"
}

variable "tags" {
  type        = map(string)
  description = "Tags for compliance resources"
  default     = {}
}
