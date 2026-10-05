# 09-dns

DNS for the landing zone: public and private zones with their records, plus
the hybrid resolver (inbound and outbound endpoints, forwarding rules, and
query logging). Used by the 07-network-dns environment, which must run after
05-network.

## What it creates

| Resource | Purpose |
|---|---|
| dns_zone (public) | zones resolvable from the internet |
| dns_zone (private) | zones visible only inside associated VPCs |
| dns_private_zone_associate | attach extra VPCs to a private zone |
| dns_recordset | the records (A, CNAME, MX, TXT and so on) |
| dns_endpoint | the inbound and outbound resolver endpoints |
| dns_resolver_rule | forward a domain to another DNS server (for example on-prem) |
| dns_resolver_rule_associate | attach a forwarding rule to VPCs |
| dns_resolver_access_log | query logging to LTS |

## Names in, IDs resolved

The inputs use names, not IDs. References inside the module (record to
zone, rule to endpoint) resolve themselves. References to things built by
05-network come in as maps from that environment's state:

- vpc_ids: VPC name to ID, for zone associations, rule associations and
  query logging
- subnet_ids: "VPC__SUBNET" to ID, for placing the resolver endpoint IPs.
  Endpoints must sit in a hub VPC; spoke subnet IDs are not exported.

By default the query-log LTS group and stream are created by this module (retention
defaults to 30 days). With manage_query_log_infra = false the module looks
them up by name instead - the deployed landing zone uses this mode, with
06-observability owning the group/stream so a fresh deploy runs strictly in
numeric order.

## How private DNS works across the whole organization

Two platform facts drive the design:

- A private zone is only visible to VPCs explicitly associated with it.
- Association only works within one account. The provider has no way to
  share a zone into another account, so a zone in the DNS account can never
  be attached directly to another account's VPC.

So the landing zone uses a central resolver instead:

1. Every subnet's DHCP hands out the inbound resolver endpoint IPs as the
   DNS servers (set by subnet_dns_servers in the network settings).
2. All servers therefore send their DNS queries to the resolver VPC, which
   can answer from:
   - the private zones associated with that VPC (so add the resolver VPC to
     every zone's VPCs list),
   - the forwarding rules for on-prem domains (each rule must also list the
     resolver VPC, or it never matches),
   - normal public DNS for everything else, as long as the zone is set to
     Recursive. A non-recursive zone answers "no such name" for anything it
     does not know.
3. Spokes can already reach the endpoint IPs through the Enterprise Router.

Zone names can be any domain, including internal ones like corp.internal.
Records must live at or under their zone's name; anything else needs its
own zone.

## Provider note

The environment calls this module with the DNS account's provider alias,
which carries the default tags. Without those tags the mandatory-tag
guardrail would block the creates.
