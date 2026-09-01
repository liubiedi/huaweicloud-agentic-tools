# CLAUDE.md — HuaweiCloud Agentic Tools

Context for AI agents in this repo. Full Terraform Landing Zone across the 9 CAF governance domains. Provider `huaweicloud/huaweicloud ~> 1.87`, Terraform `>= 1.6.3`.

## Active layout — modules-v2 / envs-v2

Build target: **`modules-v2/`** (14 modules, named by domain - no numbers; only envs are numbered) composed by **`huawei-lz/envs-v2/`** (canonical scaffold) and **`huawei-lz/envs-frasers/`** (live deploy). Env inputs + the `*.generated.tf` fan-outs (04-perimeter tagging/config, 06-observability ops/log-converge, 05-network spokes) are generated from the Excel spec by `lz_spec/build_envs.py`. The v1 catalogue was retired 2026-07-10 (archived in the workspace backups).

| modules-v2 | Domain | Feeds env |
|---|---|---|
| `organization` | Org, OUs, accounts (`for_each`), IC bootstrap, tag policy, bootstrap EP | `01-foundation` |
| `identity` | Identity Center users/groups/permission sets + IAM baseline. Sheet `03_Identity.AppPermissionSets` → env-level `app-permission-sets.generated.tf`: each row's `CustomPolicy` (a complete v5.0 custom identity policy, EP IDs baked in at spec level; authoring guide + action glossary in the workbook's `EP_Scoping` sheet) is attached verbatim to its permission set. Scoping construction: Allow service wildcards + Deny per-resource entry gates conditioned on `ForAnyValue:StringNotEqualsIfExists` / `g:EnterpriseProjectId`. | `03-identity` |
| `network` | ER hub + spoke VPCs, CFW, NAT, ELB, EIP, RAM share; per-VPC flow logs (`enable_vpc_flow_logs`: own `<vpc>-flowlog` LTS group/stream each, feeds LogConverge); spokes without a SpokeERAttachments row deploy UNATTACHED (`spoke_er_attach_enabled=false`, isolated) | `05-network` (hub+spokes, one apply) |
| `perimeter` | SCPs (8 guardrails in `var.scps`), per-account TMS predefined-tag dict (`tms-tags.tf`), **and Config/RMS org setup** (`config.tf` recorder + ORGANIZATION aggregator; `conformance.tf` org packs, template_key auto-resolved; all gated by `enable_config`) | `04-perimeter` |
| `security` | SecMaster workspace | `07-security` |
| `compliance-audit` | CTS tracker, OBS audit/access/archive buckets, KMS, LTS | `06-observability` |
| `cts-tracker` | Minimal CTS tracker, no OBS/LTS transfer (per-account fan-out for `AuditSettings.cts_no_transfer_accounts`) | `06-observability` |
| `ops-monitoring` | SMN, CES alarms | `06-observability` |
| `financial` | Cost-center enterprise projects | `02-finance` |
| `dns` | Public + private zones, record sets, hybrid resolver (in/outbound endpoints, forwarding rules, query logs); name→ID from 05-network state (`vpc_ids`/`subnet_ids`) + LTS | `08-network-dns` |
| `cfw` | CFW **rule plane** on the 05-network hub CFW (not recreated): address/domain/service groups, ACL rules (Kind eip/nat/vpc → internet/VPC border), black/white lists. Env resolves protect-object IDs (0=internet, 1=VPC) via the `cfw_firewalls` data source. Live-API rules: address-group members must NOT overlap (create returns no ID); rules use `sequence{top=0,bottom=1}` (unanchored top=0 → "dest_rule_id must not be null"); internet-border rules need `direction` (default inbound REJECTS domain groups, CFW.00400028 — module defaults nat→outbound, eip→inbound); catch-all denies (deny+any/any/any) are created via a separate `depends_on`-ordered `catchall` resource so they always land at the very bottom; **bind ALL address/service groups to the internet object** (vpc-bound groups work in rules but are INVISIBLE in the console/list APIs — canary-confirmed 2026-07-08). Frasers Property: rules are UNTAGGED (no `default_tags` on the cfw provider alias, per customer). Attack defense (attack_defense.tf, both toggles default off): `enable_anti_virus` (anti_virus on the internet object, all 7 protocols, block) + `enable_reverse_shell_defense` (every type-1 advanced IPS rule -> block IP+enabled; action-style, re-apply reasserts). IPS protection mode + virtual patching live on the FIREWALL INSTANCE (network module `cfw_ips_protection_mode`/`cfw_ips_patch_enabled`, null = console-managed). Alarm notifications (alarms.tf, all 4 toggles default off): `enable_attack_alarm`/`enable_traffic_alarm`(80%)/`enable_eip_unprotected_alarm`/`enable_threat_intel_alarm` → `cfw_alarm_config` per type, delivered to sheet-09 `alarm_topic_name` (SMN topic in the CFW account, name→URN via `smn_topics` + postcondition). | `09-network-cfw` |
| `vpn` | S2C VPN: `vpn_gateway` (attach vpc/er; auto-selects AZs via `vpn_gateway_availability_zones`; public→2 EIPs inline — eip block changes FORCE-REPLACE the gateway = new public IPs), `vpn_customer_gateway`, `vpn_connection` (`gateway_ip`=EIP by `ha_role` master=eip1/slave=eip2); PSK per connection. **ER routing**: per-gateway assoc (→`er-hybrid`, DefaultToCFW) + propagation (→er-outbound) on `er_attachment_id`; NO statics to VPN attachments (ER.04006105). **Standalone env since 2026-07** (was merged into 05-network): `module.vpn` is generated into `10-network-vpn/vpn.generated.tf`; hub/spoke IDs from the `05-network` remote state; fed by sheet `10_VPN`. | `10-network-vpn` |
| `secgroups` | Workload security groups (module 15): `networking_secgroup` + `networking_secgroup_rule`, one module call per member account (assume_role fan-out generated into `sgacl.generated.tf`). `delete_default_rules=true` - a group's SGRules rows ARE its whole policy (explicit egress row required). Rule `for_each` keys are content-addressed (`sg|dir|proto|ports|remote`) so row edits never churn siblings; `remote` = CIDR / `sg:<name>` (same account only) / `self`. SGs are region-scoped (no VPC input); NIC attachment is workload/migration scope. Sheet `11_SGACL`; NetworkACLs/ACLRules tables RESERVED (LZR-031 fails enabled rows). | `11-network-sgacl` |
| `log-aggregation` | Org LTS log aggregation in the **LTS delegated-admin** account (needs `assume_role` provider — creates OBS): `lts_log_converge_switch`, target groups/streams (TTL 90) owned by the module + `lts_log_converge` per REMOTE member (source IDs from generated per-account `lts_streams`/`lts_groups` lookups in `logconverge.generated.tf`); admin-LOCAL sources skip converge and transfer directly; `lts_transfer` (OBS cycle) per group → KMS-encrypted archive bucket (365d) | `06-observability` |
| `edge-protection` | Hub-account edge protection: `antiddos_basic` per EIP (threshold + SMN alarm by topic NAME via `smn_topics` lookup) + dedicated WAF (`waf_dedicated_instance` postPaid + auto ECS flavor via `compute_flavors`, own SG if none given, shared `waf_policy`, `waf_dedicated_domain` per row). CNAD/AAD need pre-purchased instances — out of scope | `07-security` |

**Apply order (strictly numeric since the 2026-07 renumber):** `00-bootstrap → 01-foundation → 02-finance → 03-identity → 04-perimeter → 05-network → 06-observability → 07-security → 08-network-dns → 09-network-cfw → 10-network-vpn → 11-network-sgacl` (env numbers now match the workbook sheet numbers; VPN un-merged 2026-07 into `10-network-vpn` — state key `envs/10-network-vpn` is NEW, not historical. **State keys kept their historical names** — `envs/10-security`, `envs/07-dns`, `envs/08-cfw`, `envs/09-network-sgacl` — see the backend.tf comments; never change them). The LIVE frasers tree additionally carries `envs-frasers/12-workloads` - a ONE-TIME, hand-edited workload env whose modules live INSIDE it (`12-workloads/modules/`), deliberately outside the product pipeline (no sheet/builder/emitter/catalogue); it resolves subnets/SGs/EPs by name, so 02/05/11 must be live first. Network precedes observability because the LogConverge lookups need the CFW/flow-log streams `05-network` creates; the DNS query-log LTS group/stream are OWNED by `06-observability` (created there, converged there; `08-network-dns` attaches the resolver access log with `manage_query_log_infra=false`) - a fresh deploy is strictly one pass. `08-network-dns`/`09-network-cfw` resolve VPC/subnet/firewall/route-table IDs from `05-network` remote state; `10-network-vpn` resolves hub/spoke IDs from the `05-network` remote state; `07-security` reads `05-network` (EIP/VPC IDs for module 13) + `06-observability`. Tagging is merged into `04-perimeter`; hub + spokes are one `05-network` apply (spokes self-wire ER associations off the hub's `route_table_ids` output).

**Hybrid routing + DNS (cross-module):** the ER route tables are FIXED — `er-inbound` / `er-outbound` / `er-hybrid`, hard-coded by the workbook pipeline (2026-07: the `ERRouteTables` sheet table + `inbound/outbound_route_table` settings were removed; the module variables are unchanged). VPN/DC traffic is CFW-inspected via `er-hybrid` (DefaultToCFW, auto 0/0→CFW **and auto `<spoke_private_supernet>`→CFW**) that the VPN gateway's ER attachment associates to (`09_VPN.ERAssocRouteTable`). **Both routes are required** — the hybrid table's routes are what get advertised to the on-prem peer, and a 0/0 default is often not advertised/accepted by the peer device, so the supernet route is the one on-prem reliably learns; never remove it as "duplicate of 0/0" (see engineering-notes `extra_supernet_to_cfw`). on-prem routes reach er-outbound **only via the gateway's PROPAGATION** (`ERPropRouteTable` — BGP-learned, or PeerSubnets for static tunnels). **ER rejects static routes to VPN attachments** (ER.04006105; allowed: vpc/peering/cfw/connect/5G) — there is no static fallback, so cloud→DC flows exist only while the tunnel/BGP is up. Org-wide private DNS uses the **hub-resolver pattern**: `05_Network Settings.subnet_dns_servers` points every hub+spoke subnet's DHCP at the 08-network-dns INBOUND endpoint IPs (private-zone VPC association is same-account only; the provider has no zone sharing) — resolver rules must be associated to the resolver VPC.

**Tagging model:**
- `default_tags` (Global `DefaultTags` sheet) apply to every taggable resource via each env's provider `default_tags = var.default_tags`. No `environment` tag knob.
- The **predefined-tag dictionary** lives in the `perimeter` module, applied to master + every M1 account. TF can't `for_each` providers, so `build_envs.py` generates `04-perimeter/providers.generated.tf` (one alias per M1 account) + `tagging.generated.tf` (a per-account module call) — add an account in M1 and it is created (`01-foundation`) and tagged (`04-perimeter`) automatically. Member calls run tags-only (`enable_scps=false`, `enable_predefined_tags=true`).
- **Never hand-edit `*.generated.tf`** — regenerated on every `build_envs.py` run.

**Removing an account's LAST spoke:** deleting the SpokeVPCs row also deletes that account's generated provider alias, but the state still holds the spoke's resources — `plan` then fails with "Provider configuration not present". Drop a temporary hand-written provider block (same alias, assume_role into the account) into the env — e.g. `providers-decommission.tf` — run the destroy apply, then delete the file. build_envs never touches non-generated files, so it persists until removed.

**Naming:** explicit (Excel/Settings, defaulting to `lz-*` literals). OBS bucket names + KMS aliases are **required** (no `org_name_prefix`).

## Comment hygiene in handover trees (standing rule)

Shipped HCL (modules-v2, env scaffolds, envs-frasers hand-written files, and
every comment string the emitters/templates write into generated files) must
carry ONLY concise block descriptions - what a block is and, in one line, what
it does. Lessons, live-API quirks, error codes, dates, "confirmed" notes,
design trade-offs, and historical rationale go to
**`docs/engineering-notes.md`** (internal, outside all export paths), anchored
by file + resource. Never add a caveat/war-story comment to a shipped file;
write it in the notes doc instead and keep the shipped comment short.

## Critical constraints (never change)

- CTS org tracker **must** use `region = "cn-north-4"` (global endpoint).
- SCPs **must** use `"Version": "5.0"` (OPA rejects v2012).
- OBS state backend requires exactly the 5 `skip_*` flags.
- Apply envs **strictly in order** (see above).
- **SCP packing in `perimeter`:** guardrails pack into **combined SCP documents** (one Deny statement each; Huawei caps attached SCPs at **5 per entity** incl. the system `FullAccess`). `scps.<policy>.enforce = true` → its statement goes in the **attached/LIVE** doc; `false` → a **staged, unattached** doc. Tag-governance guardrails (`require_mandatory_tags` + `require_tag_keys`) go in their OWN doc `lz-landing-zone-tag-guardrails` (`tag_policy_name`); the rest in `lz-landing-zone-guardrails` (`policy_name`). `max_statements_per_scp` (default 10) controls packing; 5,120-char limit. **`require_mandatory_tags` emits ONE Deny statement PER tag** (Huawei ANDs keys within a block, so one block only denies fully-untagged creates; separate statements OR to "deny if ANY tag missing"). **Its action list must only contain create APIs that accept tags IN the request** — OBS buckets and the vpc family (vpcs/subnets/securityGroups) tag AFTER create, so listing them denies ALL creation (SYS.0403, confirmed live 2026-07); they are excluded and covered detectively by Config. Native dry-run preview is **not** used (needs an OBS reports bucket + an Organizations trust agency). The 9 guardrails: `deny_leave_org`, `deny_root_user`, `deny_unauthorized_ram_share`, `deny_unauthorized_rms_aggregation`, `require_mandatory_tags`, `deny_public_obs`, `protect_cts_tracker`, `deny_outside_allowed_region`, `require_tag_keys` (validated vs the Frasers Property Identity Guardrails workbook + Huawei `org_03_0081`). **`require_tag_keys`** denies creates unless request tag keys ∈ an approved set (`g:TagKeys`, case-sensitive) from sheet-01 `TagPolicies`; toggled by sheet-01 `Settings.enforce_tag_keys_scp`. **Valid SCP action service codes vary by tenant** — the live API rejects some documented codes (e.g. `bss`, `dew`); the `services` defaults for `deny_root_user`/`deny_outside_allowed_region` use only tenant-confirmed codes.

## Pipeline tooling (lz_spec/)

- `build_envs.py` - workbook -> tfvars + generated fan-outs.
- `verify_pipeline.py` - regression harness: `regen-diff` (regeneration must be
  a no-op vs the live tree), `validate` (terraform validate all envs),
  `template-check` (blank template matches schema.py). Run it around EVERY
  pipeline or module change.
- `export_handover.py` - builds the customer artifact (fraser/terraform):
  modules + envs + handover-docs, module paths rewritten, `*.generated.tf`
  renamed to plain names, secrets stripped, MANIFEST.txt checksums. The
  artifact is generated - never hand-edit it; edit the sources and re-export.
- `gen_template.py <out.xlsx>` - regenerate the blank workbook template after
  any schema.py change (template-check enforces this).

## Codegen vs IaC split — handover constraint (never violate)

The Terraform tree (modules-v2 + generated envs) will be **handed over to end users without the
Excel workbook or the `lz_spec` codegen/template-gen scripts**. The IaC must be maintainable
*exclusively from the IaC*. For every future change/apply:

- **Prioritize putting logic, transformation, and heavy lifting in the codegen scripts**
  (`lz_spec/gen_template.py`, `lz_spec/build_envs.py`) — precompute at generation time rather
  than encode in HCL. Emitted envs must be plain, readable Terraform + `terraform.tfvars.json`
  a human can edit directly.
- **No clever HCL meta-programming** whose intent is only legible alongside the generator
  (deeply nested `for` comprehensions, string-encoded keys, implicit cross-file coupling).
  Simple `for_each` over well-named variable objects is the ceiling.
- **No runtime dependency on the pipeline**: `terraform plan/apply` must work from a checkout of
  the envs + modules alone. Generated files (`*.generated.tf`, tfvars.json) are convenience
  artifacts during pipeline-driven development ("never hand-edit" applies *then*); after
  handover they are ordinary HCL/JSON the end user owns and edits by hand.
- When adding a feature, ask: "could the end user adjust this behaviour by editing tfvars or a
  small obvious HCL block?" If not, move the complexity into `build_envs.py`.

## Terraform reference (source of truth)

When authoring or debugging any `huaweicloud_*` resource/data-source, consult
`../terraform-provider-huaweicloud/docs/` first (usage → `docs/resources/`, `docs/data-sources/`;
exact schema → `docs/json/**`; API/error mapping → `docs/api/**`). Prefer data-source lookups
over hardcoded enums (AZs/flavors/EPS). Full subdir map + workflow: **`../docs/provider-docs-map.md`**.

## Module pattern

Each module has `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. Every variable has `type`+`description`; every output has `description`. **Tags:** rely SOLELY on the provider `default_tags = var.default_tags` — modules must NOT inject their own tags (`local.tags = var.tags`, normally empty; resources set `tags = local.tags` or omit `tags`). No boilerplate `ManagedBy`/`Project`/`LzModule`/`Purpose`/`LzRole` tags.

## Cross-account deployment — two assume-role modes (IMPORTANT)

Both use the **master** AK/SK to assume the member's `OrganizationAccountAccessAgency` (no per-account secrets), but they yield different credentials:

| Mode | Config | Yields | Works for | Fails / wrong account |
|---|---|---|---|---|
| **Agency token** (what `build_envs._provider_alias_block` emits) | provider attrs `agency_name` + `agency_domain_name` (+ master keys, `domain_name`) | member-**scoped IAM token** only | `organizations`/SCP, IAM token ops, RMS recorder (domain-scoped), EPS, TMS | **OBS** signs with the master keys → **bucket lands in MASTER**; **v5 IAM** (`/v5/*`) → `PAP5.0046 missing x-user-profile`; **org-scoped RMS** (ORG aggregator, org conformance) → `missing request_proof` |
| **`assume_role` block** | `assume_role { agency_name=…; domain_name="<member>" }` (+ master keys) | **temp member AK/SK + SecurityToken** | **everything** incl. OBS (bucket in the member), v5 IAM (`identity_trust_agency`), org-scoped RMS | — |

**Rule:** if a *member*-account env creates **OBS buckets**, **v5 IAM agencies**, or **org-scoped RMS**, use the **`assume_role` block** (`envs-frasers/04-perimeter/config.generated.tf` does, for exactly this reason). Always set `default_tags = var.default_tags` on the cross-account provider or member SCPs (`require_mandatory_tags`) deny the create with a 403.

```hcl
provider "huaweicloud" {
  alias        = "config_admin"
  region       = var.home_region
  access_key   = var.master_access_key
  secret_key   = var.master_secret_key
  default_tags = var.default_tags          # REQUIRED or member SCPs deny creates
  assume_role {
    agency_name = local.foundation.cross_account_agency_name  # OrganizationAccountAccessAgency
    domain_name = "HW-FPCS-Sec"                               # the MEMBER account name
  }
}
```

## Providers & OPA

- Envs generate per-account provider aliases via `build_envs`. Pass the right alias to each module call: `providers = { huaweicloud = huaweicloud.<alias> }`.
- Plans are checked by `policies/opa/*.rego` (conftest): `deny-public-obs` (public ACL / missing versioning / missing encryption), `require-tags` (Environment/CostCenter/Owner/Project), `require-scp-v5` (Version 5.0), `region-allowlist` (region + unencrypted KMS + SSH from 0.0.0.0/0).
