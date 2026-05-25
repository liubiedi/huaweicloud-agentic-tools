locals {
  default_scp_deny_root = jsonencode({
    Version = "5.0"
    Statement = [
      {
        Sid      = "DenyRootActions"
        Effect   = "Deny"
        Action   = ["*"]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "iam:userType" = ["Root"]
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
        NotAction = [
          "iam:*",
          "organizations:*",
          "identitycenter:*",
          "billing:*",
          "bss:*",
        ]
        Resource = ["*"]
        Condition = {
          StringNotEquals = {
            "huaweicloud:RequestedRegion" = [var.home_region, "cn-north-4"]
          }
        }
      }
    ]
  })
}

# ── RGC pre-launch check (data source — gates landing zone creation) ────────

data "huaweicloud_rgc_pre_launch_check" "this" {}

# ── RGC Landing Zone bootstrap ──────────────────────────────────────────────
# ~25-minute create. Provisions the core OU, Log Archive account, Security
# (audit) account, optional Identity Center, and enrolls the home region.
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
    }

    accounts {
      account_name  = var.audit_account_name
      account_type  = "SECURITY"
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

# ── Resolve RGC-created core account IDs (data sources, post-create) ────────

data "huaweicloud_rgc_core_account" "log_archive" {
  account_type = "LOGGING"
  depends_on   = [huaweicloud_rgc_landing_zone.this]
}

data "huaweicloud_rgc_core_account" "audit" {
  account_type = "SECURITY"
  depends_on   = [huaweicloud_rgc_landing_zone.this]
}

# ── Organizations trusted services ──────────────────────────────────────────

resource "huaweicloud_organizations_trusted_service" "services" {
  for_each = toset(var.trusted_services)

  service = each.value

  depends_on = [huaweicloud_rgc_landing_zone.this]
}

# ── Additional OUs ───────────────────────────────────────────────────────────

data "huaweicloud_organizations_organization" "current" {
  depends_on = [huaweicloud_rgc_landing_zone.this]
}

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

resource "huaweicloud_organizations_policy" "deny_root" {
  name        = "lz-deny-root-actions"
  description = "Prevent root user actions in all member accounts"
  type        = "service_control_policy"
  content     = local.default_scp_deny_root
}

resource "huaweicloud_organizations_policy" "region_boundary" {
  name        = "lz-region-boundary"
  description = "Restrict workloads to approved regions"
  type        = "service_control_policy"
  content     = local.default_scp_region_boundary
}

resource "huaweicloud_organizations_policy_attach" "deny_root_root" {
  policy_id = huaweicloud_organizations_policy.deny_root.id
  entity_id = data.huaweicloud_organizations_organization.current.root_id
}

resource "huaweicloud_organizations_policy_attach" "region_boundary_root" {
  policy_id = huaweicloud_organizations_policy.region_boundary.id
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

resource "huaweicloud_enterprise_project" "lz" {
  name        = var.enterprise_project_name
  description = "Landing zone enterprise project for cost allocation"
  # status is computed; enable defaults to true so the project is enabled at creation
}
