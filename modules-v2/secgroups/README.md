# secgroups (module 15)

Workload security groups + rules, fully declarative. One module call per member
account (assume_role provider); rows come from the `11_SGACL` sheet
(SecurityGroups / SGRules tables) and land in `envs/09-network-sgacl`.

Design points:

- `delete_default_rules = true` - a group has ZERO implicit allows; every rule
  is a visible row. Egress must therefore be granted explicitly (the standard
  posture is one `egress / any / 0.0.0.0/0` row per group; CFW governs the
  destinations).
- `remote` accepts a CIDR, `sg:<name>` (another group in the SAME account -
  Huawei SG references cannot cross accounts) or `self`. Tier isolation is done
  with `sg:` references (e.g. db-sg ingress tcp/1433 from sg:<app-sg>).
- Security groups are region-scoped, not VPC-bound: no VPC/subnet inputs.
  Attaching groups to ECS NICs is the workload/migration team's step.
- Rule `for_each` keys are content-addressed (`sg|direction|protocol|ports|remote`),
  so adding or deleting one row never replaces sibling rules. All rule fields
  are ForceNew upstream; editing a row = destroy+create of that one rule.
- Network ACLs are NOT implemented yet. The 11_SGACL sheet reserves the
  NetworkACLs / ACLRules tables; enabled rows there fail validation (LZR-031)
  until the module grows ACL support.
