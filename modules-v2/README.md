# modules-v2

The 14 building blocks composed by the environments (canonical scaffold in
huawei-lz/envs-v2, deployed per customer from huawei-lz/envs-<name>). Each module is
plain Terraform and does one job. Folders are named by domain and carry no
numbers - only environments are numbered, because only environments have a
deploy order.

## Catalogue

| Folder | What it does |
|---|---|
| organization | Sets up the organization: accounts, OUs, Identity Center instance, tag policies |
| identity | Identity Center users, groups and permission sets, plus a per-account IAM baseline |
| network | The hub (VPCs, Enterprise Router, firewall, NAT, load balancer) and the spoke VPCs, with per-VPC flow logs. A spoke can be left detached from the router to isolate it |
| perimeter | SCP guardrails (each one can run staged or enforced), predefined tags, and Config with conformance packs |
| security | SecMaster workspace in the security account |
| compliance-audit | Org-wide CTS audit tracker, the audit/access/archive OBS buckets, KMS keys, base log groups |
| cts-tracker | Turns on a cheap CTS tracker in one account (no OBS or LTS transfer, so no storage cost). Used for accounts that only need the central org tracker |
| ops-monitoring | Central SMN notification topic and CES alarm bundles |
| financial | Cost-center enterprise projects and the predefined tag dictionary |
| dns | Public and private DNS zones, records, and the hybrid resolver (see its README for the org-wide DNS design) |
| cfw | Firewall rules for the hub firewall created by the network module |
| vpn | Site-to-cloud VPN: gateways, customer gateways, IPsec connections, router integration |
| secgroups | Workload security groups + rules per member account (delete_default_rules; sg:-references for tier isolation) |
| log-aggregation | Collects logs from every account into the log-admin account and archives them to an encrypted OBS bucket |
| edge-protection | Anti-DDoS thresholds per public IP and a dedicated WAF with protected domains |

## Conventions

- Provider pin: huaweicloud/huaweicloud version 1.87.x or newer in that
  series; Terraform 1.6.3 or newer.
- Modules use the default huaweicloud provider. The environment picks the
  target account by passing an aliased provider to each module call.
- Every variable and output has a description.
- Optional features are off by default: they turn on with enable_* flags or
  by passing a non-empty map.
- SCPs use Huawei policy version 5.0 syntax (service:resourceType:action).
  Wildcard service names are not allowed.

## Apply order

The environments already call these modules in the right order. Apply them
in number order: 00-bootstrap through 10-security. The full sequence and the
reasons behind it are in the repo CLAUDE.md; per-environment inputs come from
the Excel workbook via lz_spec/build_envs.py.
