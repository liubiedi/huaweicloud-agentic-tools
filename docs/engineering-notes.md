# Engineering notes (INTERNAL - never shipped)

Platform lessons, live-API quirks, error codes, and design rationale stripped
out of the handover HCL. The shipped modules and environments carry only
concise block descriptions (see the comment-hygiene rule in CLAUDE.md); the
full "why" lives here, anchored by file and resource. This file is outside
every export path (the artifact ships modules-v2, envs-frasers, and
huawei-lz/handover-docs only).

Add to this file whenever a change would otherwise grow a lesson/caveat
comment in a shipped tree.

---

## network module

### hub.tf
- **cfw_firewall.flavor.version**: the API rejects lowercase edition names with the opaque error "Failed to access the third-party interface" - hence the capitalization lookup.
- **CFW rule plane**: a huaweicloud_cfw_acl_rule block was once drafted here and deferred (complex `sequence` schema); the rule plane lives in the cfw module / 08-network-cfw. Do not re-add rules to the hub.
- **natv3_gateway.spec**: the API takes numeric specs "1".."5"; the workbook uses Small/Medium/Large/Extra-large names.
- **vpc_route.hub depends_on**: without the ER attachment first, the API rejects the ER id with "Invalid value ... for route nexthop".
- **elb_monitor keying**: iterating the elb_pool RESOURCE map makes for_each keys known-after-apply and breaks plan/import; key on the input names instead.
- **RAM org enablement**: org-sharing enablement / trusted-service registration are master-account APIs - from a member account they 404 ("not found for http header"). Hence huaweicloud_ram_organization lives in the env on the default provider, with the hub module call depending on it.
- **ER RAM resource type**: "er:instances" (confirmed via the permissions data source); "er:enterpriseRouter" is rejected with ram.1009 "has no permission". RAM wants full URNs or errors SYS.0400; the owner account id comes from the foundation state. Each resource type carries exactly one permission per share - bind explicitly, nothing auto-attaches.
- **allow_external_principals=false**: the default (true) would let the share target outside the org, which deny_unauthorized_ram_share denies (SYS.0403 on ram:resourceShares:create).
- **time_sleep.ram_share_propagation**: RAM association is asynchronous - a spoke attaching seconds after its account becomes a principal is denied common.01010013 er:instances:createVpcAttachment (hit live 2026-07). 60s sleep, replaced when the principal set changes.
- **er_flow_log count**: gate on plan-known conditions only; counting on the apply-time group id breaks plan.
- **Auto-wiring ordering**: the CFW association + inbound static route reference east_west_firewall_er_attachment_id (computed), which forces the EW CFW attachment to exist before route-table wiring - no explicit depends_on needed.
- **er_static_route.extra_supernet_to_cfw (\<supernet\> -> CFW on the hybrid tables)**: looks redundant next to extra_to_cfw's 0.0.0.0/0 -> CFW (same table, same next hop) and MUST NOT be "cleaned up" as such. The hybrid tables are what the VPN gateway attachment associates to, so their routes are what gets advertised to the on-prem peer; a default route is frequently not advertised or not accepted by the peer device, leaving on-prem with no path back into the cloud even though the ER side looks correct. The explicit spoke_private_supernet route is the one the peer reliably learns. It is also the safety net once propagation is enabled on a hybrid table: a propagated per-VPC prefix would otherwise beat the 0/0 default and bypass inspection. Auto-wired off spoke_private_supernet + cfw_default_route_tables (no toggle) so every customer gets it. Adopted into the frasers state 2026-07-29 (route was created in the console first; id 9e416b46-cb9c-44d6-9101-6ecab8eb98bd).
- A trailing "Optional / deferred" comment block (DNS/WAF/DC/VPN/client-VPN/traffic-mirror resource lists referencing modules-day1-resources.md) was removed; those capabilities live in their own modules.

## cfw module

### main.tf
- **Group create_before_destroy**: object_id/type are ForceNew; destroying the old group first fails while ACL rules still reference it.
- **Internet-border rule direction**: the API defaults to inbound, which REJECTS domain-group destinations with CFW.00400028 - hence module defaults nat->outbound, eip->inbound.
- **icmp permadrift**: source/dest_port are Required in the provider schema but the CFW API never echoes ports for icmp - one permanent cosmetic in-place diff per icmp rule (logicmon-to-lz-icmp). Do not chase it.
- **sequence bottom-pin**: top=0 without an anchor is rejected with "dest_rule_id must not be null"; bottom=1 lands rules in creation order.
- **Catch-all re-anchor**: replace_triggered_by keys on terraform_data.rule_ids (id set) so only create/replace re-anchors; the previous whole-map trigger replaced the 3 denies on EVERY apply (brief fail-open windows). API also canonicalizes rule address lists to ascending order (workbook lists are kept in that order to avoid permadrift).
- **Console-invisible vpc-bound groups**: address/service groups bound to the VPC protect object work in rules but are INVISIBLE in console/list APIs (canary-confirmed 2026-07-08) - bind everything to the internet object.

### attack_defense.tf
- **advanced_ips_rule is action-style**: it sets server-side state once; the provider tracks no drift (re-apply reasserts). `param` is required+create-only and is carried through from the rule's current value ("{}" fallback for blank).
- Antivirus protocol enum: 0 HTTP, 1 SMTP, 2 POP3, 3 IMAP4, 4 FTP, 5 SMB, 6 Malicious Access Control.
- **reverse-shell defense is EP-scoped** (added 2026-07-23, Frasers): the `cfw_advanced_ips_rules` data source only sends `enterprise_project_id` when set (Go source), and the CFW list API defaults to the DEFAULT project ("0") when it's omitted. A firewall in a NON-default EP (e.g. Frasers `fpcs-sg-prd-cs-cfw-01` in `fpcs-sg-prd-ep-cs`) then returns an EMPTY advanced-IPS list -> `for_each` empty -> ZERO reverse_shell resources created, a SILENT no-op (toggle true, nothing enforced). Symptom: anti-virus (object_id-scoped) works but reverse-shell doesn't. Fix: `enterprise_project_id` var on the module, passed ONLY to the DATA SOURCE that enumerates the rules; the env resolves it from `enterprise_project_name` via a `huaweicloud_enterprise_project` data source. Do NOT set it on the reverse_shell RESOURCE: it is NonUpdatable there, and rules created before the fix have it empty, so a re-apply fails with "enterprise_project_id can't be updated, -> <id>" (seen live 2026-07-25). The resource targets a rule by ips_rule_id + object_id, so it needs no EP. ips_rule_type enum: 0 sensitive-directory-scan, 1 reverse-shell.
- **reverse-shell action = 2 (block IP)** since 2026-08-04 (Frasers request; was 1 = block session). `action` enum: 0 log only, 1 block session, 2 block IP.
- **`enable_force_new = "true"` is REQUIRED on reverse_shell** (added with the action change): every argument is NonUpdatable and the provider's `config.FlexibleForceNew` default is to FAIL THE PLAN, not replace — changing the action without it errors `action can't be updated, 1 -> 2` (hit live 2026-08-04, same shape as the `enterprise_project_id` failure above). `enable_force_new` is an undocumented per-resource string attribute (`"true"`/`"false"`, validated) present on most one-time-action resources; it flips CustomizeDiff to `d.ForceNew(k)`. Prefer it over the PROVIDER-level `enable_force_new` bool, which would apply to every resource in that provider config. Safe here because the resource is action-style: Delete makes NO API call (provider source returns only a warning), so a replacement is state-removal + one POST that overwrites the server-side setting — the rule is never unset, and nothing else in the CFW is touched. Plan shape: 1 add / 1 destroy per type-1 advanced IPS rule the data source returns.

## vpn module
- **AZ auto-selection**: hardcoded AZs that do not stock the chosen flavor trigger "VPN.0001: resource not enough" - hence the per-flavor+attachment AZ data source.
- **No statics to VPN attachments**: the API rejects them with ER.04006105 "route attachment type vpn is not in [vpc, peering, cfw, connect, 5G]" (hit live 2026-07). Propagation is the ONLY path for on-prem routes; cloud->DC flows exist only while the tunnel/BGP is up.
- **Public gateway EIP blocks are create-only**: changing eip1/eip2 FORCE-REPLACES the gateway = new public IPs (drops the site until the far end reconfigures). Covered operationally in cookbooks/operations.md.

## perimeter module
- **SCP references**: guardrails validated against org_03_0081 and the customer's Identity Guardrails workbook.
- **Tenant-variable service codes**: the published catalogue (org_03_0062) lists codes this tenant REJECTS (e.g. bss, dew) - deny_root_user/deny_outside_allowed_region defaults trust only live-confirmed codes.
- **conformance.tf template params**: the parameters LISTING returns lossy "" defaults (even for strings with real defaults, e.g. NIST ecsShutdownDays "30"), and the API rejects "" with 'minLength 1'; parse the template BODY instead. Org packages require EVERY parameter explicitly (RMS.00010004) and an ENABLED recorder in the creating account (RMS.00010091).
- **config.tf**: KMS-encrypted recorder bucket needs agency KMS grants or RMS.00010006 / OBS 403 (Huawei's quick-grant agency omits KMS). The v5 trust agency only works through the ASSUME_ROLE provider - the agency-token alias throws PAP5.0046; service.Config is not a service-linked principal (PAP5.0023). Schemas validated against provider services/rms + usermanual-rms rms_04_0200.

## financial module
- **EPS authority grant is async**: an EP created seconds after the grant fails with EPS.0004 "Permission error" (hit live 2026-07 on a fresh account) - hence the one-time sleep. Deleting the grant resource does NOT revoke the authority.
- **poc EPs are permanent**: enterprise projects of type "poc" cannot be disabled (EPS.0614) - destroy fails forever. Two orphaned uat-ep-ss EPs live outside state for exactly this reason. Name poc EPs right the first time.

## log-aggregation module
- **LTS.2101 on concurrent encrypted transfers**: the first encrypted transfer triggers LTS's async self-authorization (KMS grant to op_svc_lts); concurrent creates fail LTS.2101 "kms authorisation to op_svc_lts error" (hit live 2026-07). The waves are serialized via depends_on; LTS.2101 is retryable - a second apply clears stragglers.

## security module
- **hss.tf removed** (was an all-comment deferred stub). Tracked HSS resource types for a future host-security build: hss_quota, hss_host_group, hss_policy_group(+_deploy), hss_ransomware_protection_policy, hss_vulnerability_scan_policy, hss_setting_two_factor_login_config, hss_webtamper_protection, hss_rasp_protection_policy, hss_honeypot_port_policy. Restore by confirming schemas under provider services/hss.

### spoke.tf
- **Attachment tag updates**: post-create tag changes call er:tags:batchOperation, which a MEMBER is not authorized to run on an attachment of the hub's shared ER (common.01010013) - same owner-only restriction as associations/propagations. Hence ignore_changes=[tags].
- **vpc_subnet.spoke primary_dns/secondary_dns gated on spoke_er_attach_enabled**: the hub resolver (08-network-dns INBOUND endpoint, addressed by 05_Network Settings.subnet_dns_servers) is only reachable over the ER. An UNATTACHED spoke has no route to it, so pointing its DHCP there black-holes ALL DNS in that VPC - not just internal names, since every query goes to an unreachable IP. Left unset, the provider's buildSubnetDNSList applies the region's built-in private resolver at CREATE (ap-southeast-3 -> 100.125.1.250 / 100.125.128.250), so an isolated spoke still resolves public names. Discovered on frasers 2026-07-30: fpcs-sg-sandbox-ai-vpc01 had subnet DNS 10.134.12.2/.3 with no ER attachment, no routes and no peering (the sandbox account is not even in RAMSharePrincipals, so the ER is not shared to it), leaving the VPC with no working DNS at all.
  - **CAVEAT - the guard does not repair already-deployed subnets.** primary_dns/secondary_dns/dns_list are Optional+**Computed**, so a null in config means "keep the current value": terraform reports no changes and never self-corrects an existing subnet. buildSubnetDNSList only supplies the regional default on CREATE; the UPDATE path just forwards d.Get("primary_dns") (empty string) and does not re-derive. Repair an existing black-holed subnet out of band (console/API set to the regional resolver) - because config is null and the attribute is Computed, terraform then adopts the live value permanently with no drift.

## envs (scaffold statics)

### 05-network/main.tf
- **huaweicloud_ram_organization** must run on the MASTER provider: the org-sharing write API returns 404 from a member agency. Destroying the resource is a no-op (it does not disable sharing).

## 11-workloads local modules
- **kms**: exists because the service default key evs/default only materializes on first CONSOLE use - data lookups against it fail on fresh accounts (verified live: zero keys in both workload accounts).
- **cbr policy**: the provider requires backup_quantity together with long_term_retention + time_zone (validate error otherwise); quantity is the sum of the retention categories.
- **workload-vm hostname**: user_data cloud-config only takes effect if the private image runs Cloudbase-Init with the cloud-config plugin; otherwise the migration team sets the hostname in the OS.
- **ignore_changes**: admin_pass (bootstrap-only, rotated in-OS), user_data and image_id (create-time; most_recent image lookups must not replace existing VMs).

## emitter templates
- **provider_spoke.tf.tmpl default_tags**: without it, the member's require_mandatory_tags SCP denies creates (SYS.0403). Uses the assume_role BLOCK (temporary member AK/SK), not the agency-token attrs - the cross-account ER attachment + RAM-share accept are AK/SK-signed and 404 on an agency token.

### spoke.tf (owner-provider wiring)
- Associations/propagations on the hub's shared ER fail for the recipient with common.01010013 "not authorized to perform: er:routeTables:associate" - they must run under the hub/owner provider.

### perimeter variables.tf (tag SCP exclusions)
- Including OBS/VPC-family create actions in require_mandatory_tags denies ALL creation (SYS.0403), not just untagged - their create APIs cannot carry tags (provider tags in a separate post-create call, g:RequestTag empty at create). Confirmed live 2026-07: member spoke VPC/SG creates denied even with provider default_tags + resource tags.
- Region/root-user SCP service-code defaults: the published catalogue (org_03_0062) lists codes this tenant REJECTS (e.g. dew, bss); only live-verified codes ship as defaults.

## charging_mode (pay-per-use -> monthly conversion)

Conversions are placed in the BSS console; whether Terraform notices depends on
whether the resource's Read sets `charging_mode`:

| Resource | Read sets it? | Schema | Effect of a console conversion |
|---|---|---|---|
| `compute_instance` | yes (server metadata) | Optional+Computed, **not** ForceNew | config must be updated to `prePaid` |
| `evs_volume` | yes, only when the disk has a BSS orderID | Optional+Computed+**ForceNew** | absorbed, leave unset |
| `vpc_eip` | yes (`Profile.OrderID`) | Optional+Computed | absorbed, leave unset |
| `natv3_gateway` | **no** (but `billing_info` is set) | Optional+Computed+ForceNew | invisible; read `billing_info` to tell |
| `cbr_vault` | yes | Optional+Computed+ForceNew | absorbed, but `auto_expand` is rejected on prePaid vaults |

- Leave `charging_mode` **unset** wherever possible. Optional+Computed means the
  refresh absorbs whatever BSS says, so no plan diff either way. Pinning it on a
  ForceNew resource that has *not* been converted plans a **replace** (data loss
  on EVS).
- `compute_instance` is the exception that must be pinned: Update only ever
  converts *to* prePaid and hard-errors "only support change to pre-paid" if the
  config still says `postPaid` against a converted instance.
- `period_unit`/`period` are create-only and never returned by any of these
  APIs, so they belong in `ignore_changes` next to a pinned `charging_mode`.
- Applying a `postPaid -> prePaid` diff makes Terraform place the BSS order
  itself. That is a purchase, not a state fix - convert in the console first.

Two resources cannot be converted at all:

- **traffic-billed EIPs** (`bandwidth.charge_mode = "traffic"`) - monthly EIPs
  must be bandwidth-billed, so a traffic-metered EIP stays pay-per-use.
- **auto-expanding CBR vaults** - `auto_expand` is rejected on a prePaid vault,
  and freezing a near-full vault's size fails its backups.

After a console conversion, persist it with `terraform apply -refresh-only`
(state pull backup first); a plain `plan` refreshes in memory only.

Where this lands in the trees (frasers, converted 2026-08-07):

- **network/hub.tf `huaweicloud_vpc_eip.this`** - unset by design. The one hub
  EIP is `billed_by = "traffic"` and therefore cannot go monthly at all.
- **network/hub.tf `huaweicloud_natv3_gateway.hub`** - unset by design, and must
  stay unset: Read never returns `charging_mode`, so state stays null forever
  and any pinned value is a permanent ForceNew replace of the gateway. Both
  frasers gateways are monthly; the only evidence is a non-empty `billing_info`
  (BSS order id) in state.
- **12-workloads workload-vm `huaweicloud_compute_instance.this`** - pinned
  `prePaid` with `period_unit`/`period` in `ignore_changes`, because leaving it
  `postPaid` against the converted instances fails every apply.
- **12-workloads workload-vm `huaweicloud_evs_volume.data`** - unset; the disks
  convert with their ECS. Pinning would have replaced (destroyed) the four fpcs
  volumes that were still pay-per-use at the time.
- **12-workloads cbr `huaweicloud_cbr_vault.this`** - all four stay postPaid on
  purpose. They set `auto_expand = true`, and the UAT vaults are only at their
  current size because auto-expand grew them (fpcs-sg-uat 890/936 GB = 95%);
  freezing that on a monthly plan fails backups within days.

## OBS lifecycle rules (12-workloads obs-backup)

- `transition.storage_class`: provider docs list only `WARM` (Infrequent
  Access) and `COLD` (**Archive**) — there is no `ARCHIVE` literal — but the
  schema has no validation and the OBS API in ap-southeast-3 also accepts
  `DEEP_ARCHIVE` (confirmed live 2026-08-17, prod FULL backups at 366d; clean
  read-back, no perpetual diff). `expiration.days` must be greater than every
  `transition.days` in the same rule.
- Prefixes across rules **cannot have an inclusive relationship**, so a
  bucket-wide rule cannot coexist with a per-subfolder one. Sibling prefixes
  (`sql-backups/full/`, `.../diff/`, `.../log/`) are fine; a parent
  `sql-backups/` plus any child is rejected.
- The `prefix` docs claim a leading/trailing slash is invalid, but the schema
  applies no validation and the console itself stores `sql-backups/`. Match the
  console value or the rule reads as drift.
- OBS lifecycle is **age + prefix only** - it cannot express GFS retention
  ("30 daily, 12 monthly, 6 yearly"). Mapping a GFS policy onto OBS requires the
  backup job to write each generation to its own prefix; otherwise the longest
  retention applies to every object under the prefix.
- `huaweicloud_obs_bucket_bpa` originally had
  `replace_triggered_by = [obs_bucket]`, which fired on ANY bucket change
  (including a lifecycle edit) and destroyed/recreated the BPA — public access
  unblocked for the moment between destroy and create. Fixed 2026-08-17 to key
  on `obs_bucket.this.id` instead: the id changes only on a real bucket
  replacement (rename), so in-place bucket updates no longer churn the BPA.

## Win2022std image pin (12-workloads main.tf)

- The Win2022std private image was shared FROM the central image account to
  both workload accounts; shared images keep the source image ID, so both
  accounts resolve to the same ID (`51a821db-a531-4e78-b5af-900ba6cda590`).
- The env originally looked it up with `data.huaweicloud_images_image`
  (name + visibility=shared, per account). The share was revoked/unpublished
  sometime between 2026-08-17 and 2026-08-19, and the lookup then failed with
  "your query returned no results" — which **blocks plan/apply of the whole
  env** even though the 8 live VMs are unaffected.
- Fix (2026-08-19): data sources deleted, ID pinned as a local. Safe because
  image_id is create-time only and the workload-vm module has
  `ignore_changes = [image_id, ...]`. New VM builds from this image need the
  platform team to re-share it; the pin only keeps Terraform plannable.
