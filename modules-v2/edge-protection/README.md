# 13-edge-protection

Edge protection in the network hub account: Anti-DDoS thresholds on public
IPs, plus a dedicated WAF instance with one shared policy and the protected
domains. Used by the 10-security environment.

## What it builds

| Resource | Purpose |
|---|---|
| antiddos_basic | per-EIP traffic-cleaning threshold (10 to 1000 Mbps), with an optional SMN alarm topic |
| waf_dedicated_instance | the WAF engine (pay per use; the machine flavor is picked automatically unless set) |
| networking_secgroup | a security group for the engine (80 and 443 in, everything out), created when none is supplied |
| waf_policy | one shared protection policy that all domains use |
| waf_dedicated_domain | one per protected domain; the origin is typically the hub load balancer's private address |

## Things to note

- Basic Anti-DDoS is tuning, not purchasing: every public IP already has
  free basic protection. Destroying the resource just resets the threshold
  to the default.
- Public IPs are referenced by their name from the network sheet; the
  environment resolves names to IDs from the network state.
- The advanced paid DDoS products (CNAD, AAD) are out of scope; they need
  pre-purchased instances.
- HTTPS domains need a certificate_id (a WAF certificate).
