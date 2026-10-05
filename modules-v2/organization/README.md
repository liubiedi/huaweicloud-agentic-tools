# 01-organization

The organization itself: OUs, member accounts, the Identity Center instance,
trusted services and delegated admins, and an optional tag policy. Used by the
01-foundation environment; almost everything else reads its outputs.

## What it builds

| Resource | Purpose |
|---|---|
| organizations_organization | enables Organizations in the master account |
| organizations_organizational_unit (+ child) | the OU tree, two levels deep |
| organizations_account (core + workload) | creates the member accounts and places them in their OUs |
| identitycenter_registered_region + instance | turns on IAM Identity Center |
| organizations_trusted_service | enables org-integrated services (CTS, Config, LTS, RAM and so on) |
| organizations_delegated_administrator | hands a service's org-wide admin role to a member account |
| organizations_policy + attach (tag policy) | optional org tag policy |
| enterprise_project (bootstrap) | a starter enterprise project in the master account |

## Things to note

- Account names must be 6 to 32 characters and every account email must be
  unique; both are checked by the workbook validator before this module ever
  runs.
- Creating an account auto-creates its OrganizationAccountAccessAgency, which
  is what every later environment assumes to deploy into that account.
- Accounts cannot be destroyed by Terraform in a useful way (Huawei requires
  a manual close-and-wait flow), so treat account rows as append-only.
- Delegated admins matter downstream: LTS delegation decides where
  12-log-aggregation runs, Config delegation decides where the org
  aggregator lives.
