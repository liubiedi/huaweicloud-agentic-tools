# 11-vpn

Site-to-cloud VPN: the cloud-side gateways, the customer gateways (your
on-prem devices), and the IPsec connections between them. Used by 05-network (VPN is merged into the network env and applies with the hub).


## Gateway attachment and public IPs

- attachment = er: the gateway binds to the hub Enterprise Router.
- attachment = vpc: the gateway binds to one of the hub VPCs instead.
- With network_type = public, the module creates two elastic IPs per
  gateway: eip1 (active) and eip2 (standby), sized by bandwidth_size.

Take note: the eip1 and eip2 settings only apply at creation. Changing
anything in them later (including bandwidth) REPLACES the gateway, which
means new public IPs and a dead tunnel until the on-prem side is
reconfigured. Resize bandwidth on the EIP itself via console or API.

## Availability zones

Leave a gateway's azs empty (recommended) and the module picks two valid
zones for the chosen flavor automatically. Hard-coding zones that do not
stock the flavor is what causes the "VPN.0001: resource not enough" error.

## Connections

Connections find their gateway and customer gateway by name. ha_role picks
which public IP the tunnel uses: master uses eip1, slave uses eip2. Use one
master connection for active-standby, add a slave connection for
active-active.

- psk is the IPsec pre-shared key. It belongs in the gitignored tfvars file,
  never in git.
- vpn_type is policy, static, or bgp. peer_subnets lists the on-prem CIDR
  ranges; leave it empty for bgp, which learns routes by itself.

## Routing into the Enterprise Router

The gateway's ER attachment is associated with one route table and
propagates into another (set per gateway in the inputs). On-prem routes only
enter the router through that propagation: learned over BGP, or taken from
peer_subnets for static tunnels. The router refuses static routes pointing
at a VPN attachment (error ER.04006105), so do not try to add them.
