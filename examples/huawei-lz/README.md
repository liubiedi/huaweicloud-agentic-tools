# huawei-lz — fresh Landing Zone deployment

Per-environment Terraform compositions for deploying a Huawei Cloud Landing Zone, starting from RGC bootstrap.

Wraps modules from `../../modules/` (this same repo).

## Layout

```
huawei-lz/
├── providers/
│   ├── multi-account.tf      # Provider aliases (currently master only — others
│   │                         # added as later envs need cross-account access)
│   └── variables.tf
├── envs/
│   ├── 00-bootstrap/         # Creates the OBS bucket that holds Terraform state
│   │                         # for every later env. Uses LOCAL state itself.
│   └── 01-foundation/        # RGC landing zone + Organizations baseline
│                             # (wraps modules/01-org-foundation)
└── README.md
```

## Apply order

1. **`envs/00-bootstrap`** — first, with local state. Creates the OBS state bucket + KMS key.
2. **`envs/01-foundation`** — second. Uses the OBS bucket as its S3-compatible backend. Bootstraps RGC. ~25-min apply.

Later envs (`02-network`, etc.) come after RGC is ENABLED.

## Quick start

```powershell
# 1. Set Huawei master-account credentials for both the provider AND the OBS S3 backend
$env:HW_ACCESS_KEY = "<master AK>"
$env:HW_SECRET_KEY = "<master SK>"
$env:AWS_ACCESS_KEY_ID = $env:HW_ACCESS_KEY      # the s3 backend reads AWS_* env vars
$env:AWS_SECRET_ACCESS_KEY = $env:HW_SECRET_KEY

# 2. Bootstrap the state bucket
cd envs/00-bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform apply

# 3. Foundation (RGC)
cd ../01-foundation
Copy-Item terraform.tfvars.example terraform.tfvars
Copy-Item backend.hcl.example backend.hcl
# edit terraform.tfvars — set audit_email, identity_store_email, etc.
# edit backend.hcl — set bucket (from step 2), region, endpoints.s3
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

## What's in scope right now

Only RGC + Organizations baseline (`01-foundation`). Add subsequent envs (`02-network`, `03-security-audit`, etc.) as you exercise more of the module library.
