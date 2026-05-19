variable "home_region" {
  type        = string
  description = "Region for shared resources"
}

variable "shared_obs_buckets" {
  type = list(object({
    name          = string
    storage_class = optional(string, "STANDARD")
    versioning    = optional(bool, true)
    kms_key_id    = optional(string, "")
    shared_account_ids = list(string)
  }))
  description = "Centrally-managed OBS buckets to create and share"
  default     = []
}

variable "sfs_turbo_instances" {
  type = list(object({
    name              = string
    vpc_id            = string
    subnet_id         = string
    security_group_id = string
    availability_zone = string
    size              = number
    share_type        = optional(string, "STANDARD")
  }))
  description = "SFS Turbo shared file system instances"
  default     = []
}

variable "kms_keys" {
  type = list(object({
    alias            = string
    description      = string
    rotation_enabled = optional(bool, true)
    pending_days     = optional(number, 7)
    shared_account_ids = list(string)
  }))
  description = "KMS keys to create and share via RAM"
  default     = []
}

variable "shared_images" {
  type = list(object({
    name        = string
    image_url   = string
    os_type     = optional(string, "Linux")
    description = optional(string, "")
    shared_account_ids = list(string)
  }))
  description = "IMS images to import and share to spoke accounts"
  default     = []
}

variable "enterprise_project_id" {
  type        = string
  description = "Enterprise project ID for cost allocation"
  default     = "0"
}

variable "tags" {
  type        = map(string)
  description = "Tags for shared resources"
  default     = {}
}
