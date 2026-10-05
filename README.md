# HuaweiCloud Landing Zone - Terraform library

The module library for the Excel-driven HuaweiCloud Landing Zone. The
environments that compose these modules live in the pipeline repo
(`huawei-cloud-landing-zone-pipeline`):

- `terraform/scaffold/` - canonical environment scaffold (new deployments)
- `terraform/envs-example/` - reference tree built from the example spec

Customer deployments are kept outside both repos, one tree each, and ship with
the pipeline's handover export.

Provider pin: `huaweicloud/huaweicloud ~> 1.87`, Terraform `>= 1.6.3`.

## Layout

| Path | What it is |
|---|---|
| `modules-v2/` | The 14 modules, named by domain (organization, network, cfw, ...). See its README for the catalogue. Only environments carry numbers, because only environments have a deploy order (00-bootstrap through 11-network-sgacl). |
| `policies/` | OPA/conftest checks run against plans (public OBS, mandatory tags, SCP v5 syntax, region allowlist). |
| `docs/` | PRD and internal design notes. |

Environment inputs (`terraform.tfvars.json`) and the per-account fan-out files
are generated from the customer spec by the pipeline's `lzctl build`;
`lzctl check` is the regression harness. The generation
pipeline is optional tooling: every environment plans and applies as plain
Terraform without it.

The original RGC-based v1 catalogue (numbered `modules/`, `envs/00-05`,
`providers/multi-account.tf`) was retired on 2026-07-10; it lives in the
workspace backup archives if ever needed for reference.

Working rules for agents and humans: see `CLAUDE.md`.
