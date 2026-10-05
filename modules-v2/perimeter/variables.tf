# --- Perimeter inputs ---

variable "environment" {
  type        = string
  default     = "shared"
  description = "Environment label."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto created policies."
}

# --- SCP target and organization identity ---

variable "enable_scps" {
  type        = bool
  default     = true
  description = "Create the SCPs. Set false for tags-only (per-account) invocations of this module."
}

variable "attach_target_id" {
  type        = string
  default     = ""
  description = "Entity the SCPs attach to (typically the Workloads OU ID from 01-foundation). Avoid org root - it would impact core accounts. Required when enable_scps = true."
}

variable "org_id" {
  type        = string
  default     = ""
  description = "Organization ID (foundation organization_id output). Combined with root_ou_id to derive the allowed org path used by the RAM-share and RMS-aggregation guardrails."
}

variable "root_ou_id" {
  type        = string
  default     = ""
  description = "Org root ID (foundation root_id output). Combined with org_id as '<org_id>/<root_ou_id>/*' for the cross-org guardrails (#3 RAM, #4 RMS - both StringNotMatch, where '*' is a real wildcard), unless a policy sets allowed_org_path explicitly."
}

variable "policy_name" {
  type        = string
  default     = "lz-landing-zone-guardrails"
  description = "Base name for the combined SCP document(s) holding the NON-tag guardrails. A numeric suffix is appended per chunk (e.g. '-1'); staged docs get '-staged-N'."
}

variable "tag_policy_name" {
  type        = string
  default     = "lz-landing-zone-tag-guardrails"
  description = "Name for the dedicated tag-governance SCP document (mandatory tags + approved tag keys). Used as-is when the tag statements fit one document; a numeric suffix is appended only if they overflow into multiple chunks."
}

variable "max_statements_per_scp" {
  type        = number
  default     = 10
  description = "Max guardrail statements packed into one SCP document. Keeps each document under Huawei's 5,120-char limit AND the number of attached docs under the per-entity quota of 5 (FullAccess takes one slot, so <=4 usable). Applies independently to the general (policy_name) and tag (tag_policy_name) documents. A typical baseline (~7 non-tag, ~4 tag statements) packs into one document each."
}

# --- Guardrail settings ---

variable "scps" {
  description = "The 8 Landing Zone guardrails. Per block: enabled (create the SCP), enforce (true = attach it at attach_target_id -> LIVE; false = created but not attached/inert), name (explicit policy name), plus that policy's own settings."
  type = object({

    # Organization membership protection
    deny_leave_org = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "deny-leave-organization")
    }), { enabled = false })

    # Root user restriction
    deny_root_user = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "deny-root-user")
      # Verified service scope
      services = optional(list(string), [
        "iam", "organizations", "ram", "cts",
        "ecs", "evs", "vpc", "rds", "obs", "elb", "as", "nat", "dms", "css", "cce",
      ])
    }), { enabled = false })

    # RAM organization boundary
    deny_unauthorized_ram_share = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "deny-unauthorized-ram-share")
      # Organization path override
      # Note: Blank derives the root path; wildcard matching uses StringNotMatch.
      allowed_org_path = optional(string, "")
    }), { enabled = false })

    # Config organization boundary
    deny_unauthorized_rms_aggregation = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "deny-unauthorized-rms-aggregation")
      # Organization path override
      # Note: Blank derives the root path; wildcard matching uses StringNotMatch.
      allowed_org_path = optional(string, "")
    }), { enabled = false })

    # Mandatory tag enforcement
    require_mandatory_tags = optional(object({
      enabled        = optional(bool, true)
      enforce        = optional(bool, false)
      name           = optional(string, "deny-create-without-mandatory-tags")
      mandatory_tags = optional(list(string), ["Project", "Owner", "Environment", "BU"])
      # Note: OBS and VPC resources are tagged after creation; Config checks their compliance.
      actions = optional(list(string), [
        "ecs:cloudServers:create", "evs:volumes:create", "rds:instances:create",
        "elb:loadbalancers:create", "elb:listeners:create",
        "as:scalingGroups:create", "nat:natGateways:create", "dms:instances:create",
        "css:clusters:create", "cce:cluster:create",
      ])
    }), { enabled = false })

    # Public bucket restriction
    deny_public_obs = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "deny-public-obs")
      # Note: Blank disables public-access exceptions.
      exception_tag_key   = optional(string, "")
      exception_tag_value = optional(string, "approved")
      public_acls         = optional(list(string), ["public-read", "public-read-write"])
      actions = optional(list(string), [
        "obs:bucket:CreateBucket", "obs:bucket:PutBucketAcl",
        "obs:bucket:PutBucketPolicy", "obs:bucket:PutBucketPublicAccessBlock",
      ])
    }), { enabled = false })

    # CTS tracker protection
    protect_cts_tracker = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "protect-cts-tracker")
      # Note: Empty allows no administrator exception.
      admin_principal_urns = optional(list(string), [])
      actions              = optional(list(string), ["cts:tracker:delete", "cts:tracker:update", "cts:tracker:disable"])
      # Note: The resource URN must include a region field.
      tracker_resource = optional(string, "cts:*:*:tracker:system")
    }), { enabled = false })

    # Allowed region enforcement
    # Note: Global services and OBS are excluded because requested-region context is unreliable.
    deny_outside_allowed_region = optional(object({
      enabled         = optional(bool, true)
      enforce         = optional(bool, false)
      name            = optional(string, "deny-outside-allowed-region")
      allowed_regions = optional(list(string), ["ap-southeast-3"])
      # Verified regional service scope
      services = optional(list(string), [
        "ecs", "evs", "vpc", "rds", "elb", "as", "nat", "dms", "css", "cce",
      ])
    }), { enabled = false })

    # Approved tag keys
    # Note: Keys are case-sensitive; an empty key list disables this guardrail.
    require_tag_keys = optional(object({
      enabled  = optional(bool, true)
      enforce  = optional(bool, false)
      name     = optional(string, "require-mandatory-tag-keys")
      tag_keys = optional(list(string), [])
      # Note: Exclude OBS and VPC create actions because their tags are applied after creation.
      actions = optional(list(string), [
        "ecs:cloudServers:create", "evs:volumes:create", "rds:instances:create",
        "elb:loadbalancers:create", "elb:listeners:create",
        "as:scalingGroups:create", "nat:natGateways:create", "dms:instances:create",
        "css:clusters:create", "cce:cluster:create",
      ])
    }), { enabled = false })
  })
  default = {}
}

# --- Config administration ---

variable "home_region" {
  type        = string
  default     = "ap-southeast-3"
  description = "Home region - default for the recorder OBS-channel region when config.recorder_bucket_region is blank."
}

variable "enable_config" {
  type        = bool
  default     = false
  description = "Create the Config (RMS) resource recorder + org aggregator. Only set true on the Config admin-account invocation of this module."
}

variable "config" {
  description = "Config (RMS) org setup. recorder = per-account Config tracker (OBS [+ SMN]); aggregator = ORGANIZATION-type aggregated compliance view. The recorder's OBS bucket and IAM agency are created when create_recorder_bucket / create_recorder_agency are true (else referenced by name, assumed to exist). Ignored unless enable_config = true."
  type = object({
    enable_recorder = optional(bool, true)
    # Recorder trust agency
    recorder_agency_name = optional(string, "rms_tracker_trust_agency")
    recorder_bucket_name = optional(string, "")
    # Note: Blank uses home_region.
    recorder_bucket_region  = optional(string, "")
    recorder_all_supported  = optional(bool, true)
    recorder_resource_types = optional(list(string), [])
    recorder_smn_topic_urn  = optional(string, "")

    # Recorder prerequisite ownership
    create_recorder_bucket = optional(bool, true)
    # Note: Encryption requires KMS grants for the recorder agency.
    recorder_bucket_kms_encrypt = optional(bool, false)
    # Member recorder access
    recorder_bucket_writer_domains = optional(list(string), [])
    create_recorder_agency         = optional(bool, true)
    # Recorder trust principal
    recorder_agency_delegated_service = optional(string, "service.Config")
    # Recorder agency policies
    recorder_agency_roles = optional(list(string), ["ConfigTrackAgencyPolicy", "OBSFullAccessPolicy"])

    enable_aggregator = optional(bool, true)
    aggregator_name   = optional(string, "lz-org-aggregator")
  })
  default = {}
}

variable "conformance_packs" {
  description = "Org-wide Config conformance packs. Each: name (readable, also the resource name), enabled, template_key (optional override - blank = auto-resolve by name from the templates data source), excluded_accounts. Ignored unless enable_config = true."
  type = list(object({
    name         = string
    enabled      = optional(bool, true)
    template_key = optional(string, "")
    # Conformance-pack resource name
    pack_name         = optional(string, "")
    excluded_accounts = optional(list(string), [])
    # Template parameter overrides
    # Note: Values use JSON encoding; omitted parameters use template defaults.
    vars = optional(map(string), {})
  }))
  default = []
}

# --- Predefined tag dictionary ---

variable "enable_predefined_tags" {
  type        = bool
  default     = false
  description = "Create the TMS predefined-tag dictionary in the target account from var.predefined_tags."
}

variable "predefined_tags" {
  type = list(object({
    key    = string
    values = optional(list(string), [])
  }))
  default     = []
  description = "Tag dictionary: each key plus its allowed values (empty values = any value, emitted as '*')."
}
