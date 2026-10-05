# 05-security

SecMaster in the security account: one workspace that ingests logs from the
other accounts through cloud log resources. Host security (HSS) and database
security (DBSS) are wired in but switched off by default.

## Optional per-member workspaces

Set enable_member_workspaces = true and fill member_workspace_bindings to
add view workspaces in the security account that mirror workspaces owned by
member accounts. Each member must have created its own workspace first.

## If an apply fails on a field name

Alert rule triggers, the cloud log resource product_name (it is case
sensitive), and HSS quota flavors can vary by provider version and region.
If plan or apply complains, check the provider documentation for the pinned
version and adjust.
