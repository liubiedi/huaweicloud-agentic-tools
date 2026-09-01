# Module 4 - data perimeter (Service Control Policies) + TMS predefined tags.
#
# Two independent functions, selected by flags:
#   - SCPs            : enable_scps = true (org-level; attaches at attach_target_id)
#   - Predefined tags : enable_predefined_tags = true (per-account TMS dictionary)
#
# The SCPs are the Landing Zone identity guardrails. Each policy in var.scps
# is self-contained: enabled / enforce / name + that policy's own settings.
# Authored as v5.0 JSON per the Huawei Organizations SCP reference.

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

# ---- SCP attach + org identity ----

variable "enable_scps" {
  type        = bool
  default     = true
  description = "Create the SCPs. Set false for tags-only (per-account) invocations of this module."
}

variable "attach_target_id" {
  type        = string
  default     = ""
  description = "Entity the SCPs attach to (typically the Workloads OU ID from module 1). Avoid org root - it would impact core accounts. Required when enable_scps = true."
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

# ---- The 8 guardrail SCPs ----
# Each block is independent. An omitted block defaults to enabled = false, so the
# Layer-2 builder only needs to emit the policies the customer turned on.

variable "scps" {
  description = "The 8 Landing Zone guardrails. Per block: enabled (create the SCP), enforce (true = attach it at attach_target_id -> LIVE; false = created but not attached/inert), name (explicit policy name), plus that policy's own settings."
  type = object({

    # 1. Deny leaving the organization.
    deny_leave_org = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "deny-leave-organization")
    }), { enabled = false })

    # 2. Deny root user usage.
    # Huawei bans wildcard service names in actions, so we enumerate services as
    # "<service>:*:*". Includes the sensitive control-plane services + major
    # workload services. Override `services` to widen/narrow coverage.
    deny_root_user = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "deny-root-user")
      # Only service codes confirmed to apply in this tenant; widen via
      # scps.deny_root_user.services after verifying each code.
      services = optional(list(string), [
        "iam", "organizations", "ram", "cts",
        "ecs", "evs", "vpc", "rds", "obs", "elb", "as", "nat", "dms", "css", "cce",
      ])
    }), { enabled = false })

    # 3. Deny resource sharing with unauthorized organization (RAM).
    deny_unauthorized_ram_share = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "deny-unauthorized-ram-share")
      # "" = derive '<org_id>/<root_ou_id>/*'. Uses StringNotMatch, where '*' is a
      # real wildcard. (Do NOT use StringNotLike: it treats '*' literally - substring
      # match - and would deny every share.)
      allowed_org_path = optional(string, "")
    }), { enabled = false })

    # 4. Deny aggregation authorization from unauthorized organization (RMS/Config).
    deny_unauthorized_rms_aggregation = optional(object({
      enabled = optional(bool, true)
      enforce = optional(bool, false)
      name    = optional(string, "deny-unauthorized-rms-aggregation")
      # "" = derive '<org_id>/<root_ou_id>/*'. Uses StringNotMatch (wildcard) - the
      # trailing '*' is a real wildcard matching path descendants.
      allowed_org_path = optional(string, "")
    }), { enabled = false })

    # 5. Deny resource create/update without mandatory tags.
    require_mandatory_tags = optional(object({
      enabled        = optional(bool, true)
      enforce        = optional(bool, false)
      name           = optional(string, "deny-create-without-mandatory-tags")
      mandatory_tags = optional(list(string), ["Project", "Owner", "Environment", "BU"])
      # OBS buckets and the VPC family are intentionally excluded: their
      # create APIs cannot carry tags, so listing them would deny all
      # creation. Their tag compliance is covered detectively by Config.
      actions = optional(list(string), [
        "ecs:cloudServers:create", "evs:volumes:create", "rds:instances:create",
        "elb:loadbalancers:create", "elb:listeners:create",
        "as:scalingGroups:create", "nat:natGateways:create", "dms:instances:create",
        "css:clusters:create", "cce:cluster:create",
      ])
    }), { enabled = false })

    # 6. Deny public OBS unless exception-tagged.
    deny_public_obs = optional(object({
      enabled             = optional(bool, true)
      enforce             = optional(bool, false)
      name                = optional(string, "deny-public-obs")
      exception_tag_key   = optional(string, "") # "" = no exception (public non-overridable)
      exception_tag_value = optional(string, "approved")
      public_acls         = optional(list(string), ["public-read", "public-read-write"])
      actions = optional(list(string), [
        "obs:bucket:CreateBucket", "obs:bucket:PutBucketAcl",
        "obs:bucket:PutBucketPolicy", "obs:bucket:PutBucketPublicAccessBlock",
      ])
    }), { enabled = false })

    # 7. Protect the default CTS tracker from disable/delete.
    protect_cts_tracker = optional(object({
      enabled              = optional(bool, true)
      enforce              = optional(bool, false)
      name                 = optional(string, "protect-cts-tracker")
      admin_principal_urns = optional(list(string), []) # [] = no exception (nobody may modify)
      actions              = optional(list(string), ["cts:tracker:delete", "cts:tracker:update", "cts:tracker:disable"])
      tracker_resource     = optional(string, "cts:*:*:tracker:system") # region field required (MISSING_URN_REGION if empty)
    }), { enabled = false })

    # 8. Deny resource creation outside the allowed region(s).
    # Service names can't be wildcarded, so we enumerate REGIONAL services as
    # "<service>:*:*". Global/region-less services (iam, organizations, cts,
    # identitycenter, ram, bss, billing) and OBS are deliberately excluded - they
    # have no reliable g:RequestedRegion and denying them by region would break the org.
    deny_outside_allowed_region = optional(object({
      enabled         = optional(bool, true)
      enforce         = optional(bool, false)
      name            = optional(string, "deny-outside-allowed-region")
      allowed_regions = optional(list(string), ["ap-southeast-3"])
      # Only service codes verified to apply in this tenant; widen via
      # scps.deny_outside_allowed_region.services after verifying each code.
      services = optional(list(string), [
        "ecs", "evs", "vpc", "rds", "elb", "as", "nat", "dms", "css", "cce",
      ])
    }), { enabled = false })

    # 9. Deny create actions unless the request carries approved tag keys
    # (g:TagKeys, case-sensitive). Hard counterpart to the advisory tag policies:
    # tag_keys are filled by the Layer-2 builder from the sheet-01 TagPolicies
    # (case preserved). Actions are ENUMERATED (same proven create-action list as
    # require_mandatory_tags) - Huawei rejects a wildcard service name. Folded into
    # the consolidated SCP. An empty tag_keys list drops the guardrail.
    require_tag_keys = optional(object({
      enabled  = optional(bool, true)
      enforce  = optional(bool, false)
      name     = optional(string, "require-mandatory-tag-keys")
      tag_keys = optional(list(string), [])
      # Same exclusions as require_mandatory_tags: OBS + the vpc family tag their
      # resources AFTER create, so request-tag conditions would deny ALL creates.
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

# ---- Config (RMS) org setup ----
# Set enable_config = true (with the module called under the Config admin
# account's provider) to create the resource recorder + org aggregator. Left
# off for the SCP and tags-only invocations.

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
    # Huawei's system-created recorder trust agency (correct service.Config /
    # sts:agencies:assume trust). Created by Config console "Auto create agency".
    recorder_agency_name    = optional(string, "rms_tracker_trust_agency")
    recorder_bucket_name    = optional(string, "")
    recorder_bucket_region  = optional(string, "") # "" = home_region
    recorder_all_supported  = optional(bool, true)
    recorder_resource_types = optional(list(string), [])
    recorder_smn_topic_urn  = optional(string, "")

    # Create-if-not-exists prerequisites. true = this module creates the
    # bucket/agency; false = reference recorder_bucket_name / recorder_agency_name
    # as already-existing (e.g. Huawei's auto-created rms_tracker_agency).
    create_recorder_bucket      = optional(bool, true)
    recorder_bucket_kms_encrypt = optional(bool, false) # KMS encryption needs extra agency KMS grants (OBS 403 otherwise)
    # Centralized recorder bucket: member account domain IDs allowed to write to
    # this bucket (so member-account recorders can write back to the central Sec
    # bucket). Adds a cross-account OBS bucket policy. Only used on the bucket-owning
    # (admin) invocation. Empty = no cross-account policy (single-account bucket).
    recorder_bucket_writer_domains    = optional(list(string), [])
    create_recorder_agency            = optional(bool, true)
    recorder_agency_delegated_service = optional(string, "service.Config")                                         # trust principal in the agency trust_policy (the Config service)
    recorder_agency_roles             = optional(list(string), ["ConfigTrackAgencyPolicy", "OBSFullAccessPolicy"]) # policies on the trust agency (match Huawei's rms_tracker_trust_agency)

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
    # Explicit org conformance-pack resource name (the one name the pack carries as
    # it deploys org-wide). Blank = a slug derived from `name`.
    pack_name         = optional(string, "")
    excluded_accounts = optional(list(string), [])
    # Per-parameter overrides (var_key => var_value, JSON-encoded as the template
    # expects). Any parameter not listed uses the template's default_value. Needed
    # where a template default is invalid - e.g. PCI DSS 'trackBucket' default is ""
    # but the template enforces minLength 3.
    vars = optional(map(string), {})
  }))
  default = []
}

# ---- Predefined tags (TMS tag dictionary) ----
# Set enable_predefined_tags = true (with enable_scps = false) to invoke this
# module purely as a per-account tag-dictionary writer.

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
