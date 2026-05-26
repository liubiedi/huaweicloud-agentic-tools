locals {
  # Huawei SCP v5 syntax:
  #   - Action / Resource are STRINGS for wildcards ("*"), or lists of strings
  #     in the 3-field form "<service>:<type>:<operation>" / "<service>:<region>:<domain-id>:<resource-type>:<path>".
  #   - "iam:*" or "organizations:*" are NOT valid action shapes.
  #   - Condition keys use the `g:` namespace for global keys (e.g. g:RequestedRegion).
  #   - g:RequestedRegion is not honored by all services — global services (IAM, Organizations,
  #     Identity Center, billing) effectively bypass it, which is the behavior we want here.
  # Huawei SCP v5 syntax notes:
  # - Action / Resource are JSON STRING ARRAYS.
  # - Each Action element is "<service>:<type>:<operation>". Huawei FORBIDS
  #   wildcards in the service-name position — "*:*:*" is rejected with
  #   "SCP_SYNTAX_ERROR_WILDCARD_IN_SERVICE_NAME_OF_ACTION". You must enumerate
  #   service names; wildcards are fine for type and operation ("iam:*:*").
  # - Resource elements use "*" as the all-resources wildcard.
  # - Condition keys use the `g:` namespace for global keys.
  #
  # The action lists below cover common high-risk services. Adjust to your
  # environment — services not enumerated are NOT denied.
  default_scp_deny_root = jsonencode({
    Version = "5.0"
    Statement = [
      {
        Sid    = "DenyRootActions"
        Effect = "Deny"
        Action = [
          "iam:*:*",
          "organizations:*:*",
          "identitycenter:*:*",
          "bss:*:*",
          "billing:*:*",
        ]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "g:UserType" = ["root"]
          }
        }
      }
    ]
  })

  default_scp_region_boundary = jsonencode({
    Version = "5.0"
    Statement = [
      {
        Sid    = "DenyOutOfRegionOperations"
        Effect = "Deny"
        Action = [
          "ecs:*:*",
          "vpc:*:*",
          "evs:*:*",
          "obs:*:*",
          "rds:*:*",
          "elb:*:*",
          "nat:*:*",
          "vpn:*:*",
          "er:*:*",
          "ces:*:*",
          "lts:*:*",
          "aom:*:*",
          "secmaster:*:*",
          "hss:*:*",
          "cfw:*:*",
          "waf:*:*",
          "kms:*:*",
        ]
        Resource = ["*"]
        Condition = {
          StringNotEquals = {
            "g:RequestedRegion" = [var.home_region, "cn-north-4"]
          }
        }
      }
    ]
  })
}

# ── RGC pre-launch check (data source — gates landing zone creation) ────────

data "huaweicloud_rgc_pre_launch_check" "this" {}

# ── Pre-create LOGGING + SECURITY accounts via Organizations ────────────────
# WORKAROUND for huaweicloud provider bug in v1.91.0: when account_id is unset
# on the RGC landing_zone accounts block, the provider serializes accountId=""
# in the request body, which the Huawei API rejects (regex "^[\\w-]+$"). See:
#   huaweicloud/services/rgc/resource_huaweicloud_rgc_landing_zone.go
#   func filterOrganizationStructureEmptyValue — strips empty account_email
#   and phone but forgot account_id.
# By creating the accounts via huaweicloud_organizations_account first and
# passing their IDs, we hit RGC's enroll-existing path and avoid the bug.

resource "huaweicloud_organizations_account" "log_archive" {
  name  = var.log_archive_account_name
  email = var.log_archive_email

  tags = {
    ManagedBy = "terraform"
    Project   = "landing-zone"
    LzRole    = "log-archive"
  }
}

resource "huaweicloud_organizations_account" "audit" {
  name  = var.audit_account_name
  email = var.audit_email

  tags = {
    ManagedBy = "terraform"
    Project   = "landing-zone"
    LzRole    = "audit"
  }
}

# ── RGC Landing Zone bootstrap ──────────────────────────────────────────────
# ~25-minute create. Enrolls the two pre-created core accounts, sets up the
# core OU + optional Identity Center + region enrollment + log buckets.
# Most fields are NonUpdatable — change them and the LZ is destroyed/recreated.

resource "huaweicloud_rgc_landing_zone" "this" {
  home_region             = var.home_region
  identity_center_status  = var.enable_identity_center ? "ENABLE" : "DISABLE"
  identity_store_email    = var.identity_store_email
  cloud_trail_type        = var.enable_org_aggregation
  deny_ungoverned_regions = var.deny_ungoverned_regions

  region_configuration_list {
    region                      = var.home_region
    region_configuration_status = "ENABLED"
  }

  organization_structure {
    organizational_unit_type = "CORE"
    organizational_unit_name = var.core_ou_name

    accounts {
      account_name = var.log_archive_account_name
      account_type = "LOGGING"
      account_id   = huaweicloud_organizations_account.log_archive.id
    }

    accounts {
      account_name  = var.audit_account_name
      account_type  = "SECURITY"
      account_id    = huaweicloud_organizations_account.audit.id
      account_email = var.audit_email
    }
  }

  logging_configuration {
    logging_bucket {
      retention_days  = var.logging_retention_days
      enable_multi_az = var.logging_multi_az
    }
    access_logging_bucket {
      retention_days  = var.access_logging_retention_days
      enable_multi_az = var.logging_multi_az
    }
  }

  lifecycle {
    precondition {
      condition     = data.huaweicloud_rgc_pre_launch_check.this.id != ""
      error_message = "RGC pre-launch check did not complete; aborting landing zone setup."
    }
  }
}

# ── Organizations trusted services ──────────────────────────────────────────

resource "huaweicloud_organizations_trusted_service" "services" {
  for_each = toset(var.trusted_services)

  service = each.value

  depends_on = [huaweicloud_rgc_landing_zone.this]
}

# ── Organization (read-only) ────────────────────────────────────────────────
# RGC creates and owns the org. We don't manage it from Terraform — there's
# one org per account, and trying to create another always conflicts.
#
# Caveat for tag_policy: only service_control_policy type is enabled by
# default. To use tag policies (var.enable_default_tag_policy or
# var.tag_policies), enable tag_policy type at the org root manually first:
#   Huawei console > Organizations > Policies > Tag policies > Enable
# That's a one-time click per organization. Until done, leave
# enable_default_tag_policy = false and tag_policies = [].
#
# depends_on ensures the data source waits for RGC bootstrap to create the
# org before reading it. RGC LZ is already-created by the time anything
# reads this, so no cascade.
data "huaweicloud_organizations_organization" "current" {
  depends_on = [huaweicloud_rgc_landing_zone.this]
}

# ── Additional OUs ───────────────────────────────────────────────────────────

resource "huaweicloud_organizations_organizational_unit" "additional" {
  for_each = { for ou in var.additional_ous : ou.name => ou }

  name      = each.value.name
  parent_id = each.value.parent_id != "" ? each.value.parent_id : data.huaweicloud_organizations_organization.current.root_id
}

# ── Member account vending ───────────────────────────────────────────────────

resource "huaweicloud_organizations_account" "members" {
  for_each = { for acct in var.additional_member_accounts : acct.name => acct }

  name        = each.value.name
  email       = each.value.email
  description = each.value.description

  tags = {
    ManagedBy = "terraform"
    Project   = "landing-zone"
  }
}

# ── Default SCPs ─────────────────────────────────────────────────────────────

# NOTE on default SCP content:
# Huawei rejects wildcards ("*", "?") in the service-name position of an
# Action — i.e. "*:*:*" is INVALID. A working SCP must enumerate explicit
# service names like ["iam:*:*", "organizations:*:*", ...].
# Because the right action enumeration is account/use-case specific, these
# default SCPs ship OPT-IN and currently use placeholder content. Flip the
# enable_* flag below AND replace local.default_scp_* content with your own
# enumeration before turning these on. See variables.tf.

resource "huaweicloud_organizations_policy" "deny_root" {
  count = var.enable_default_deny_root_scp ? 1 : 0

  name        = "lz-deny-root-actions"
  description = "Prevent root user actions on critical services in all member accounts"
  type        = "service_control_policy"
  content     = local.default_scp_deny_root
}

resource "huaweicloud_organizations_policy" "region_boundary" {
  count = var.enable_default_region_boundary_scp ? 1 : 0

  name        = "lz-region-boundary"
  description = "Restrict workloads to approved regions"
  type        = "service_control_policy"
  content     = local.default_scp_region_boundary
}

resource "huaweicloud_organizations_policy_attach" "deny_root_root" {
  count = var.enable_default_deny_root_scp ? 1 : 0

  policy_id = huaweicloud_organizations_policy.deny_root[0].id
  entity_id = data.huaweicloud_organizations_organization.current.root_id
}

resource "huaweicloud_organizations_policy_attach" "region_boundary_root" {
  count = var.enable_default_region_boundary_scp ? 1 : 0

  policy_id = huaweicloud_organizations_policy.region_boundary[0].id
  entity_id = data.huaweicloud_organizations_organization.current.root_id
}

# ── Default tag policy (opt-in starter) ──────────────────────────────────────
# Enforces presence of a configurable list of standard tag keys. Defaults to
# off; flip enable_default_tag_policy = true to ship with the LZ.

locals {
  default_tag_policy_content = jsonencode({
    tags = {
      for key in var.default_tag_policy_required_keys : key => {
        tag_key = { "@@assign" = key }
      }
    }
  })
}

resource "huaweicloud_organizations_policy" "default_tags" {
  count = var.enable_default_tag_policy ? 1 : 0

  name        = "lz-required-tags"
  description = "Require standard tag keys on all taggable resources"
  type        = "tag_policy"
  content     = local.default_tag_policy_content
}

resource "huaweicloud_organizations_policy_attach" "default_tags_root" {
  count = var.enable_default_tag_policy ? 1 : 0

  policy_id = huaweicloud_organizations_policy.default_tags[0].id
  entity_id = data.huaweicloud_organizations_organization.current.root_id

  # WARNING: this will FAIL with "bad request for policy type disabled" unless
  # tag_policy type has been enabled at the org root manually via the Huawei
  # console. Set enable_default_tag_policy = false until you've done that.
}

# ── Custom tag policies ───────────────────────────────────────────────────────

resource "huaweicloud_organizations_policy" "tag_policies" {
  for_each = { for tp in var.tag_policies : tp.name => tp }

  name        = each.value.name
  description = each.value.description
  type        = "tag_policy"
  content     = each.value.content
}

# ── Enterprise project ────────────────────────────────────────────────────────

# Opt-in. EPS is separately permissioned; many master accounts don't have it.
# Set create_enterprise_project = false (default) to skip.
resource "huaweicloud_enterprise_project" "lz" {
  count = var.create_enterprise_project ? 1 : 0

  name        = var.enterprise_project_name
  description = "Landing zone enterprise project for cost allocation"
}
