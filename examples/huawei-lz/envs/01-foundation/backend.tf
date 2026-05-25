# OBS via Terraform's s3-compatible backend.
# The endpoints argument is a block, so it can't cleanly be passed as a flat
# -backend-config key. Use a backend.hcl file instead:
#
#   terraform init -backend-config=backend.hcl
#
# Copy backend.hcl.example to backend.hcl and fill in.
#
# The s3 backend reads AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars at
# init time — set them to your Huawei master AK/SK before running init.

terraform {
  backend "s3" {
    key = "envs/01-foundation/terraform.tfstate"

    # The five flags below are mandatory for the OBS S3-compat backend —
    # `terraform init` fails silently without them.
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true

    # bucket, region, endpoints — supplied via backend.hcl
  }
}
