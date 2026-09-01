# 02-identity

Identity and permissions. Two independent halves, each behind an enable flag.

## Identity Center content (runs in the master account)

Set enable_identity_center_content = true. Needs identity_store_id and
identity_center_instance_id from the foundation outputs.

Creates Identity Center users, groups, memberships, permission sets, policy
attachments, account assignments, the password policy, the MFA setting, and
registered regions.

## IAM baseline (runs once per account)

Set enable_iam_baseline = true and call the module with a provider that
points at the target account. Creates that account's password policy, login
policy, protection policy, and service agencies.

Two agencies are created by default:

- cts-to-lz-audit-bucket: lets CTS write audit events to the central audit
  bucket
- lts-to-lz-archive-bucket: lets LTS move logs to the central archive bucket

## If an apply fails on a field name

A few Identity Center and IAM resources have field names that vary between
provider versions (password policy, MFA setting, login policy, protection
policy). If terraform plan or apply complains about an unknown argument,
check the provider documentation for your pinned version and adjust the
field name.
