# 12-log-aggregation

Collects logs from every account into one place. Runs in the log-admin
account (the LTS delegated admin). Used by the 06-observability environment.

## What it builds

| Resource | Purpose |
|---|---|
| lts_log_converge_switch | lets this account receive logs from the others |
| lts_group / lts_stream (target) | the collection groups and streams, kept 90 days by default |
| lts_log_converge | one per remote account, mapping its source stream to a target here |
| kms_key + obs_bucket (archive) | the encrypted, versioned archive bucket, kept 365 days by default |
| lts_transfer | moves each group's logs into the archive bucket on a cycle |

## How sources are handled

- A source in a REMOTE account is converged into a target group here named
  agg-ACCOUNT-GROUP, then transferred to the archive.
- A source already IN the admin account skips the converge step and
  transfers straight to the archive, keeping its own retention setting.

## Things to note

- The provider for this module must use an assume_role block, not the
  agency-token style. The module creates an OBS bucket, and under token mode
  the bucket would land in the master account instead.
- Source stream IDs are found by data lookups in the generated file. If a
  source stream is deleted, the plan fails immediately, which is intended:
  it tells you a mapping points at nothing.
- Deleting a converge mapping does not delete its target group or stream.
  Clean those up by hand when retiring a mapping.
- The very first transfer into the encrypted bucket can fail with LTS.2101
  while Huawei sets up the KMS permission for the LTS service in the
  background. Just run apply again.
