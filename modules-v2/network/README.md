# 03-network

Hub and spoke networking. One module, two call modes, picked by enable
flags.

## Hub mode (network hub account)

```hcl
module "network_hub" {
  source    = "../../../huaweicloud-agentic-tools/modules-v2/network"
  providers = { huaweicloud = huaweicloud.lz_infra }

  enable_hub = true
  hub_vpcs   = { ... }   # dmz, access, shared services
  # plus Enterprise Router, firewall, NAT, EIP, load balancer, RAM share inputs
}
```

## Spoke mode (once per spoke VPC, in the owning account)

```hcl
module "network_spoke_app_prod" {
  source    = "../../../huaweicloud-agentic-tools/modules-v2/network"
  providers = { huaweicloud = huaweicloud.lz_app_prod }

  enable_spoke   = true
  spoke_vpc_name = "app-prod-vpc"
  spoke_vpc_cidr = "10.1.0.0/16"
  spoke_subnets  = [{ name = "workload-az1", cidr = "10.1.1.0/24", az = "az1" }]
  spoke_er_id    = data.terraform_remote_state.network_hub.outputs.er_id
}
```

Set spoke_er_attach_enabled = false to create the VPC without connecting it
to the Enterprise Router. The spoke then runs isolated: no route to the hub
or the other spokes.

## Flow logs

Set enable_vpc_flow_logs = true and every VPC (hub and spoke) gets its own
log group, log stream and flow log, all named VPCNAME-flowlog. Retention is
flow_log_retention_days (default 90).

## CIDR sizing guide

| VPC | Minimum | Recommended |
|---|---|---|
| dmz (NAT, load balancer, ingress) | /20 | /16 |
| access (DC and VPN termination) | /23 | /20 |
| shared services (DNS resolver, AD) | /22 | /16 |
| each spoke | /20 | /16 |

The firewall attaches straight to the Enterprise Router; it does not need
its own VPC.

## Optional extras

More resource families (DNS, WAF, Direct Connect, traffic mirroring) are
listed at the bottom of hub.tf. All are off by default behind enable_*
flags.
