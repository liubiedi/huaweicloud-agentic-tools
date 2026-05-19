# Manually Managed Resources

Services with partial or no Terraform provider coverage that require console or API configuration.

| Service | Gap | Workaround |
|---|---|---|
| **Anti-DDoS / AAD** | `huaweicloud_aad_*` resources exist but EIP binding is limited | Configure AAD protection for critical EIPs via console post-apply |
| **Data Security Center (DSC)** | `huaweicloud_dsc_instance` available but data classification rules lack full coverage | Instance via TF, classification rules via console |
| **APM (Application Performance Management)** | No Terraform resources in provider v1.87 | Configure APM agents and dashboards manually |
| **Cloud Operations Center (COC)** | Partial coverage — runbook creation not supported | Create runbook templates in COC console |
| **BSS Budgets** | `huaweicloud_bms_budget` has limited support | Set account-level budgets in Cost Center console |
| **One Access (IdP Federation)** | Configured via `huaweicloud_identity_provider` but requires SAML metadata exchange | Upload IdP metadata and SP metadata manually after TF creates the provider resource |
| **WAF bot management** | Bot-manager rules not fully exposed in provider | Configure bot behavior rules in WAF console after domain onboarding |

## Tracking

Open issues against this list as the provider adds coverage. When a resource becomes fully supported, move its configuration to the appropriate Terraform module and remove it from this table.
