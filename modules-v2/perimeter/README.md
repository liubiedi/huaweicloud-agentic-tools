# 04-perimeter

Three things: the SCP guardrails, the predefined tag dictionary per account,
and the Config (RMS) organization setup with conformance packs.

## How the guardrails are packaged

Huawei allows at most 5 attached SCPs per target, and the built-in
FullAccess policy uses one slot. So instead of one policy per guardrail,
each guardrail becomes one Deny statement and the statements are packed into
combined policy documents.

Each guardrail block in var.scps has two switches:

- enabled: create the statement at all
- enforce: true puts it in the LIVE document attached to the target OU;
  false keeps it in a staged document that exists but is not attached

Documents are split automatically if they grow past the 5120 character
limit.

## The guardrails

| Key | Blocks |
|---|---|
| deny_leave_org | member accounts leaving the organization |
| deny_root_user | any action by the root user |
| deny_unauthorized_ram_share | resource shares to organizations outside ours |
| deny_unauthorized_rms_aggregation | Config aggregation from outside organizations |
| require_mandatory_tags | creating resources without the mandatory tags |
| deny_public_obs | making OBS buckets public (unless tagged with the approved exception tag) |
| protect_cts_tracker | disabling or deleting the audit tracker |
| deny_outside_allowed_region | creating resources outside the allowed regions |
| require_tag_keys | creating resources without the approved tag keys (case sensitive) |

Two safe defaults: if deny_public_obs has no exception tag configured,
public buckets are denied outright with no exception. If protect_cts_tracker
has no admin URNs listed, nobody is exempt.

## Things to note

- The tag guardrails (require_mandatory_tags, require_tag_keys) may only
  list create actions that accept tags in the create request. OBS buckets
  and the VPC family (VPC, subnet, security group) only get tags after
  creation. Listing them blocks ALL their creates with a SYS.0403 error.
- Some service codes in the Huawei documentation are rejected by the API
  (for example bss, dew, vpn). The defaults here contain only codes the
  platform accepts; test before widening them.

## Attach target

Attach the SCPs to the Workloads OU, not the organization root. Attaching
at the root would also hit the master, logging and security accounts and
could lock admins out.

## Config (RMS) setup

Config is a global service, so the organization-wide pieces run from one
account: the Config delegated admin. Set enable_config = true on the module
call whose provider is that account. It creates:

- The resource recorder (turns Config on) writing to an OBS bucket. The
  bucket and the IAM agency the recorder needs are created for you by
  default; set create_recorder_bucket or create_recorder_agency to false to
  reuse existing ones by name instead.
- The organization aggregator, which pulls every member account's compliance
  data into one view.
- The conformance packs from var.conformance_packs. Each pack's template key
  is looked up at plan time from the live template catalogue (the keys
  differ per tenant and region, so they are never hard coded). If a name
  cannot be matched, the plan fails and prints the available keys.

If the recorder fails with STS5.1001 after the agency was created by
Terraform, create the agency once through the Config console instead (it
sets up the exact trust the service expects) and set
create_recorder_agency = false.

## Example

```hcl
scps = {
  deny_leave_org              = { name = "deny-leave-organization", enforce = true }  # live
  deny_root_user              = { name = "deny-root-user", enforce = false }          # staged
  deny_outside_allowed_region = { name = "deny-outside-allowed-region", allowed_regions = ["ap-southeast-3"] }
  # leave a block out to skip that guardrail entirely
}
```
