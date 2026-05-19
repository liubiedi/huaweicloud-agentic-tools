# CLAUDE.md — HuaweiCloud Agentic Tools

Context file for Claude Code / AI agents working in this repository.

## Repository purpose

Complete Terraform implementation of the Huawei Cloud Landing Zone across all 9 governance domains.
Provider: `huaweicloud/huaweicloud ~> 1.87` | Terraform `>= 1.6.3`

## Module catalogue

| Module | Path | Key resources |
|---|---|---|
| org-foundation | `modules/01-org-foundation` | `huaweicloud_rgc_landing_zone`, `huaweicloud_organizations_*`, `huaweicloud_enterprise_project` |
| identity-center | `modules/02-identity-center` | `huaweicloud_identitycenter_*` |
| iam-baseline | `modules/03-iam-baseline` | `huaweicloud_identity_*`, `huaweicloud_identity_agency` |
| network-hub | `modules/04-network-hub` | `huaweicloud_er_*`, `huaweicloud_cfw_*`, `huaweicloud_nat_*`, `huaweicloud_ram_resource_share` |
| network-spoke | `modules/05-network-spoke` | `huaweicloud_vpc`, `huaweicloud_vpc_subnet`, `huaweicloud_er_vpc_attachment` |
| public-services | `modules/06-public-services` | `huaweicloud_elb_*`, `huaweicloud_waf_*`, `huaweicloud_dns_*` |
| shared-resources | `modules/07-shared-resources` | `huaweicloud_kms_key`, `huaweicloud_obs_bucket`, `huaweicloud_sfs_turbo`, `huaweicloud_images_*` |
| security-center | `modules/08-security-center` | `huaweicloud_secmaster_*`, `huaweicloud_hss_*`, `huaweicloud_dbss_*`, `huaweicloud_csms_*` |
| audit-logging | `modules/09-audit-logging` | `huaweicloud_cts_tracker`, `huaweicloud_lts_*`, `huaweicloud_obs_bucket` |
| compliance-config | `modules/10-compliance-config` | `huaweicloud_rms_*` |
| ops-monitoring | `modules/11-ops-monitoring` | `huaweicloud_ces_*`, `huaweicloud_aom_*`, `huaweicloud_smn_*`, `huaweicloud_fgs_*` |
| finance-governance | `modules/12-finance-governance` | `huaweicloud_organizations_policy` (tag), `huaweicloud_rms_policy_assignment` |
| data-perimeter | `modules/13-data-perimeter` | `huaweicloud_organizations_policy` (SCP), `huaweicloud_vpcep_*` |

## Critical constraints (never change these)

- CTS org tracker **must** use `region = "cn-north-4"` — global service endpoint
- SCPs **must** use `"Version": "5.0"` — v2012 syntax will be rejected by OPA
- OBS state backend requires exactly 5 `skip_*` flags — do not remove them
- `envs/05-perimeter` `enforce_mode` defaults to `false` — verify VPC endpoints before enabling
- Apply envs **strictly in order**: 00 → 01 → 02 → 03 → 04 → 05

## Module pattern

Every module has: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`.
Every variable must have `type` and `description`.
Every output must have `description`.
Tags: always merge `local.tags` which extends the standard set with `var.tags`.

## Multi-account providers

Provider aliases in `providers/multi-account.tf`:
- `huaweicloud` (default) — master account
- `huaweicloud.network_ops` — network operations account
- `huaweicloud.logging` — log archive account (region: cn-north-4)
- `huaweicloud.security_ops` — security operations account
- `huaweicloud.ops_monitoring` — O&M monitoring account
- `huaweicloud.public_service` — public service account
- `huaweicloud.sandbox` — sandbox account

Pass the correct provider alias when calling modules:
```hcl
module "network_hub" {
  source    = "../../modules/04-network-hub"
  providers = { huaweicloud = huaweicloud.network_ops }
  ...
}
```

## OPA guardrails

All plans are checked by `policies/opa/*.rego` via conftest:
- `deny-public-obs.rego` — blocks public OBS ACLs, missing versioning, missing encryption
- `require-tags.rego` — requires Environment, CostCenter, Owner, Project on all taggable resources
- `require-scp-v5.rego` — rejects SCPs not using Version 5.0
- `region-allowlist.rego` — blocks deployment outside approved regions; rejects unencrypted KMS, SSH from 0.0.0.0/0
