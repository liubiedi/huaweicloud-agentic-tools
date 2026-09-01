# HuaweiCloud Landing Zone - Terraform library

The module library for the Excel-driven HuaweiCloud Landing Zone. The
environments that compose these modules live in `../huawei-lz/`:

- `../huawei-lz/envs-v2/` - canonical environment scaffold (new deployments)
- `../huawei-lz/envs-frasers/` - the live Frasers deployment
- `../huawei-lz/handover-docs/` - operator docs and day-2 cookbooks shipped
  with the customer handover

Provider pin: `huaweicloud/huaweicloud ~> 1.87`, Terraform `>= 1.6.3`.

## Layout

| Path | What it is |
|---|---|
| `modules-v2/` | The 14 modules, named by domain (organization, network, cfw, ...). See its README for the catalogue. Only environments carry numbers, because only environments have a deploy order (00-bootstrap through 10-security). |
| `policies/` | OPA/conftest checks run against plans (public OBS, mandatory tags, SCP v5 syntax, region allowlist). |
| `docs/` | PRD and internal design notes. |

Environment inputs (`terraform.tfvars.json`) and the per-account fan-out files
are generated from the customer Excel workbook by `../lz_spec/build_envs.py`;
`../lz_spec/verify_pipeline.py` is the regression harness. The generation
pipeline is optional tooling: every environment plans and applies as plain
Terraform without it.

The original RGC-based v1 catalogue (numbered `modules/`, `envs/00-05`,
`providers/multi-account.tf`) was retired on 2026-07-10; it lives in the
workspace backup archives if ever needed for reference.

Working rules for agents and humans: see `CLAUDE.md`.
