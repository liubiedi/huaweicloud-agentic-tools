# 06-compliance-audit

Runs in the logging account. Owns the audit backbone:

- The organization-wide CTS tracker (records every account's API activity)
- Three OBS buckets: audit events, access logs, and the log archive
- One KMS key per bucket
- The base LTS setup: five log groups with streams, transfers to OBS,
  cross-account write access, and keyword alarms

## Tracker region

The organization tracker is created in the provider's region. Huawei only
supports the org tracker in certain regions (historically cn-north-4 and
ap-southeast-1), and the failure shows up at apply time, not plan time. If
your home region is not supported, pass a provider alias pinned to a
supported region for this module.

## Cross-account log writers

Member accounts push logs in through the lts_cross_account_access resources,
one per account ID. They authenticate with the same
OrganizationAccountAccessAgency that exists in every member account, so no
extra setup is needed per account.
