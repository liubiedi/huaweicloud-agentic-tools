# 10-cfw

The rule set for the Cloud Firewall. The firewall itself is created by
03-network; this module only manages what runs on it: address groups, domain
groups, service groups, ACL rules, and black/white lists. Used by the 08-network-cfw
environment, which must run after 05-network.

The environment reads the firewall ID from the network state and passes in
the firewall's two protected objects:

- internet_object_id: the internet border (north-south traffic)
- vpc_object_id: the VPC border (east-west traffic between VPCs)

## Friendly values

The Huawei API wants numeric codes; the module accepts readable words and
translates them:

- Border: internet or vpc
- Rule kind: eip (internet border), nat (internet border for NAT), vpc
  (VPC border)
- Action: allow or deny. Status: enable or disable.
- Protocol: tcp, udp, icmp, icmpv6, any
- List type: blacklist or whitelist. Direction: source or destination.
- Rule direction (internet-border rules only): inbound or outbound. Leave it
  blank and nat rules default to outbound, eip rules to inbound. Inbound rules
  cannot point at a domain group (the API rejects them with CFW.00400028).

## Rule source, destination and service tokens

Each is a comma-separated list:

- Source: an IP or CIDR, addrgroup:NAME, or any
- Destination: same as source, plus domaingroup:NAME
- Service: any, app:NAME for layer-7 apps (for example app:HTTPS),
  svcgroup:NAME, or an inline protocol/sourceport/destport (for example
  tcp/any/443)

Rules are pinned to the bottom of the list as they are created. If precedence
needs changing later, reorder in the console. IPv4 only.

Catch-all rules (deny with source, destination and service all set to any) are
created last, after every other rule, so they always end up at the very bottom
of the list. Use them for a whitelist-only setup. When you add or change any
other rule later, the catch-alls are automatically recreated so they stay at
the bottom - expect them to show as "replaced" in the plan, and know the deny
is briefly absent while that happens.

## Things to note

- Members of one address group must not overlap each other; the create
  fails with "ID is not found in API response". Collapse nested CIDRs
  before adding them.
- Rules cannot be created without a position anchor; the module handles
  this by pinning every rule to the bottom.
- Always set Border to internet on address and service groups. Groups
  bound to the vpc border work in rules but do not appear in the
  console's object group pages.
