# --- Identity inputs ---

variable "environment" {
  type        = string
  default     = "shared"
  description = "Environment label applied to tags"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged into the module's standard tag set"
}

# --- Feature switches ---

variable "enable_identity_center_content" {
  type        = bool
  default     = false
  description = "Create IC users/groups/permission_sets/account_assignments. Run once in the master account."
}

variable "enable_iam_baseline" {
  type        = bool
  default     = false
  description = "Apply per-account IAM baseline (password/login/protection policies + service agencies). Run in each account via provider alias."
}

# --- Identity Center content ---

variable "identity_store_id" {
  type        = string
  default     = ""
  description = "Identity store ID from 01-foundation output. Required when enable_identity_center_content = true."
}

variable "identity_center_instance_id" {
  type        = string
  default     = ""
  description = "IC instance ID from 01-foundation output. Required when enable_identity_center_content = true."
}

variable "session_duration" {
  type        = string
  default     = "PT8H"
  description = "ISO-8601 duration for permission set sessions. PT8H = 8 hours."
}

variable "groups" {
  type = list(object({
    name        = string
    description = optional(string, "")
  }))
  default = [
    { name = "lz-admins", description = "Full landing zone administrators" },
    { name = "lz-developers", description = "Workload developers" },
    { name = "lz-security", description = "Security operations" },
    { name = "lz-billing", description = "Billing readers" },
    { name = "lz-readonly", description = "Read-only access" },
  ]
  description = "IC workforce groups."
}

variable "users" {
  type = list(object({
    user_name    = string
    display_name = string
    family_name  = string
    given_name   = string
    email        = string
    group_names  = list(string)
  }))
  default     = []
  description = "IC workforce users. group_names lists must match groups defined above."
}

variable "permission_sets" {
  type = map(object({
    description      = string
    session_duration = optional(string, "PT8H")
    # System policy names (v2012)
    system_policies = optional(list(string), [])
    # Identity policy names (v5)
    system_identity_policies = optional(list(string), [])
  }))
  default = {
    LzAdministrator = {
      description     = "Full administrative access to all services"
      system_policies = ["FullAccess"]
    }
    LzDeveloper = {
      description     = "Developer access - compute, storage, databases. No IAM write."
      system_policies = ["Tenant Guest", "Server Administrator"]
    }
    LzSecurityAuditor = {
      description     = "Read-only access to security services and logs"
      system_policies = ["Security Administrator"]
    }
    LzBillingViewer = {
      description     = "Billing and cost management read-only"
      system_policies = ["BSS Administrator"]
    }
    LzReadOnly = {
      description     = "Read-only access to all resources"
      system_policies = ["Tenant Guest"]
    }
  }
  description = "Permission sets to create in IC. Keyed by PS name."
}

variable "account_assignments" {
  type = list(object({
    account_id     = string
    group_name     = string
    permission_set = string
  }))
  default     = []
  description = "Bind (group, permission_set, account) triples. account_id from 01-foundation's accounts output."
}

variable "registered_regions" {
  type        = list(string)
  default     = []
  description = "Regions where Identity Center can issue session credentials."
}

# --- Identity Center policies ---

variable "ic_password_policy" {
  type = object({
    min_password_length   = optional(number, 12)
    require_uppercase     = optional(bool, true)
    require_lowercase     = optional(bool, true)
    require_numbers       = optional(bool, true)
    require_symbols       = optional(bool, true)
    password_max_age_days = optional(number, 90)
    # Note: Identity Center allows a maximum of 1.
    password_reuse_prevention = optional(number, 1)
  })
  default     = {}
  description = "IC instance-wide password policy. Applied when enable_identity_center_content = true."
}

variable "ic_mfa_management" {
  type = object({
    mfa_required        = optional(bool, true)
    user_create_otp_url = optional(bool, true)
    enabled_mfa_methods = optional(list(string), ["webauthn", "sms"])
  })
  default     = {}
  description = "IC MFA management settings."
}

# --- Account IAM baseline ---

variable "iam_password_policy" {
  type = object({
    minimum_password_length   = optional(number, 12)
    maximum_password_age      = optional(number, 90)
    password_reuse_prevention = optional(number, 12)
    minimum_password_age      = optional(number, 0)
    password_requirements     = optional(string, "Must contain at least 2 of the following 4 character types: uppercase letters, lowercase letters, numbers, special characters")
  })
  default     = {}
  description = "Per-account v3 IAM password policy."
}

variable "iam_login_policy" {
  type = object({
    account_validity_period    = optional(number, 0)
    custom_info_for_login      = optional(string, "")
    lockout_duration           = optional(number, 15)
    login_failed_times         = optional(number, 5)
    period_with_login_failures = optional(number, 15)
    session_timeout            = optional(number, 60)
    show_recent_login_info     = optional(bool, true)
  })
  default     = {}
  description = "Per-account v3 IAM login policy."
}

variable "iam_protection_policy" {
  type = object({
    operation_protection = optional(bool, true)
    attributes           = optional(list(string), ["email", "mobile"])
    self_management      = optional(bool, true)
    self_verification    = optional(bool, true)
  })
  default     = {}
  description = "Per-account v3 IAM protection policy (step-up MFA for high-risk operations)."
}

variable "service_agencies" {
  type = list(object({
    name        = string
    description = optional(string, "")
    # Delegated service principal
    delegated_service = string
    # System policy names
    policies      = optional(list(string), [])
    all_resources = optional(bool, true)
    duration      = optional(string, "FOREVER")
    # Note: Required when all_resources is false.
    project_name = optional(string, "")
  }))
  default = [
    {
      name              = "cts-to-lz-audit-bucket"
      description       = "Allow CTS to write events to the central lz-audit OBS bucket"
      delegated_service = "service.CTS"
      policies          = ["OBS OperateAccess"]
    },
    {
      name              = "lts-to-lz-archive-bucket"
      description       = "Allow LTS to transfer logs to the lz-lts-archive OBS bucket"
      delegated_service = "service.LTS"
      policies          = ["OBS OperateAccess"]
    },
  ]
  description = "Cross-service agencies pre-created at Day-1 baseline. Each delegates one Huawei service to act in this account."
}
