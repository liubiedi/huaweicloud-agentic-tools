# HuaweiCloud Agentic Tools — Landing Zone Terraform

Complete Terraform implementation of the Huawei Cloud Landing Zone reference architecture across all nine governance domains.

**Provider:** `huaweicloud/huaweicloud ~> 1.87` | **Terraform:** `>= 1.6.3`

---

## Repository structure

```
.
├── modules/                    # Reusable building blocks
│   ├── 01-org-foundation/      # RGC, Organizations, SCPs, OUs, account vending
│   ├── 02-identity-center/     # IAM Identity Center, SSO, permission sets
│   ├── 03-iam-baseline/        # Per-account IAM hardening, agencies, policies
│   ├── 04-network-hub/         # Enterprise Router, Cloud Firewall, NAT, VPN, RAM share
│   ├── 05-network-spoke/       # Per-account VPC + ER attachment
│   ├── 06-public-services/     # ELB, WAF, DNS, resolver endpoints
│   ├── 07-shared-resources/    # KMS, OBS, SFS Turbo, IMS shared images
│   ├── 08-security-center/     # SecMaster, HSS, DBSS, CSMS, KMS
│   ├── 09-audit-logging/       # CTS org tracker, LTS groups/streams, OBS archive
│   ├── 10-compliance-config/   # RMS recorder, aggregator, conformance packs, rules
│   ├── 11-ops-monitoring/      # Cloud Eye, AOM, SMN, FunctionGraph runbooks
│   ├── 12-finance-governance/  # Tag policies, cost RMS rules
│   └── 13-data-perimeter/      # SCPs enforcement, VPC endpoints, OBS bucket policies
│
├── envs/                       # Environment compositions (deploy in order)
│   ├── 00-bootstrap/           # State backend OBS bucket + CI agency
│   ├── 01-foundation/          # Modules 01–03
│   ├── 02-network/             # Modules 04–07
│   ├── 03-security-audit/      # Modules 08–10
│   ├── 04-ops-finance/         # Modules 11–12
│   └── 05-perimeter/           # Module 13 (apply last)
│
├── providers/
│   ├── multi-account.tf        # Aliased providers for all LZ accounts
│   └── variables.tf            # Provider-level variables
│
├── policies/
│   ├── opa/                    # OPA/Conftest guardrail policies
│   │   ├── deny-public-obs.rego
│   │   ├── require-tags.rego
│   │   ├── require-scp-v5.rego
│   │   └── region-allowlist.rego
│   └── checkov/
│       └── .checkov.yaml
│
├── docs/
│   └── manually-managed.md     # Services with partial TF coverage
│
├── .github/workflows/lz-deploy.yml  # CI/CD pipeline
├── .pre-commit-config.yaml
└── terraform.tfvars.example
```

---

## Deployment order

Apply environments strictly in sequence — each env reads outputs from the previous via `terraform_remote_state`.

```
00-bootstrap  →  01-foundation  →  02-network  →  03-security-audit  →  04-ops-finance  →  05-perimeter
```

> **Note:** `envs/05-perimeter` deploys SCPs and the OBS VPCEP-only policy. The `enforce_mode` variable defaults to `false`. Enable it only after verifying all spoke VPCs have OBS VPC endpoints deployed.

---

## Quick start

### 1. Bootstrap state backend

```bash
cd envs/00-bootstrap
cp ../../terraform.tfvars.example terraform.tfvars
# Fill in master_access_key, master_secret_key, tfstate_bucket_name
terraform init
terraform apply
```

### 2. Set credentials for CI

Configure these GitHub Actions secrets and variables:

| Secret | Value |
|---|---|
| `HWC_MASTER_ACCESS_KEY` | Master account AK |
| `HWC_MASTER_SECRET_KEY` | Master account SK |
| `INFRACOST_API_KEY` | Infracost API key (optional) |

| Variable | Example |
|---|---|
| `LZ_TFSTATE_BUCKET` | `my-lz-tfstate-prod` |
| `LZ_HOME_REGION` | `cn-east-3` |

### 3. Configure tfvars for each env

```bash
cd envs/01-foundation
cp ../../terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — see inline comments
```

### 4. Apply via CI or manually

```bash
# Manual apply (for initial bring-up)
export AWS_ACCESS_KEY_ID=<master_ak>
export AWS_SECRET_ACCESS_KEY=<master_sk>

terraform init -backend-config="bucket=my-lz-tfstate-prod" \
               -backend-config="region=cn-east-3"
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

---

## Key design decisions

| Decision | Rationale |
|---|---|
| S3 backend on OBS | No native HWC TF backend; requires 5 `skip_*` flags in every `backend "s3"` block |
| CTS org tracker hard-coded to `cn-north-4` | Global service constraint — do not make this a variable |
| SCPs use `Version: "5.0"` | v5 syntax required by Huawei Cloud; OPA policy rejects v2012 |
| `enforce_mode = false` on perimeter | Prevent lockout before VPC endpoints are in place |
| CI concurrency groups per env | Prevents concurrent runs from corrupting shared state |
| One state file per env composition | Limits blast radius of a corrupted state file |

---

## Pre-commit hooks

```bash
pip install pre-commit
pre-commit install
```

Hooks run: `terraform fmt`, `terraform validate`, `tflint`, `checkov`, `terraform-docs`.

---

## Services with partial Terraform coverage

See [docs/manually-managed.md](docs/manually-managed.md) for Anti-DDoS, DSC, APM, COC, and BSS Budgets.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
