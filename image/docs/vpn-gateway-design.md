# Bastion VPN Gateway Design (Site-to-Site IPsec)

This document describes the **VPN gateway** subsystem: multi-peer site-to-site IPsec between bastions using StrongSwan swanctl, runtime peer YAML, nftables forward policy, NAT bypass, and policy routing.

Road-warrior (client-to-site) VPN is documented in [vpn-design.md](vpn-design.md). Network forwarding context is in [network-design.md](network-design.md). Additional connectivity scenarios and variants are in [ipsec-vpn-connectivity-design.md](ipsec-vpn-connectivity-design.md).

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Configuration Model](#configuration-model)
4. [Peer YAML Schema](#peer-yaml-schema)
5. [Scripts and Files](#scripts-and-files)
6. [strongSwan Per-Peer Configuration](#strongswan-per-peer-configuration)
7. [Traffic Selectors and Directions](#traffic-selectors-and-directions)
   - [How ingress and egress peers work together](#how-ingress-and-egress-peers-work-together)
   - [Per-direction behaviour](#per-direction-behaviour)
   - [Paired egress + ingress: end-to-end flows](#paired-egress--ingress-end-to-end-flows)
   - [Reachability matrix](#reachability-matrix)
   - [Road-warrior cross-site access](#road-warrior-cross-site-access)
8. [nftables and NAT Bypass](#nftables-and-nat-bypass)
9. [Policy Routing and Admin Routes](#policy-routing-and-admin-routes)
10. [Runtime Management](#runtime-management)
11. [Multi-Cloud Peering Example (OVH ↔ AWS)](#multi-cloud-peering-example-ovh--aws)
12. [Terraform Integration](#terraform-integration)
13. [Troubleshooting](#troubleshooting)

---

## Overview

The VPN gateway allows a bastion to establish **site-to-site IPsec tunnels** to remote bastions or upstream gateways. Unlike road-warrior VPN (`vpn.type`), gateway peers are:

- Defined in **per-peer YAML files** under `/data/strongswan/peers/`
- Managed at runtime via `manage_vpn_gateway_peer` (no image rebuild required)
- Independent of which road-warrior protocol (if any) is enabled

Typical use case: OVH OpenStack bastion (egress) ↔ AWS bastion (ingress), bridging admin subnets and optionally road-warrior client subnets.

---

## Architecture

```mermaid
flowchart TB
  subgraph ovh [OVH Bastion - egress]
    OYAML[aws-us-east-1.yaml]
    OCONF[peer-aws-us-east-1.conf]
    OSS[strongSwan charon]
    ONFT[nft mycs_vpn_gateway]
  end

  subgraph aws [AWS Bastion - ingress]
    AYAML[ovh-uk1.yaml]
    ACONF[peer-ovh-uk1.conf]
    ASS[strongSwan charon]
    ANFT[nft mycs_vpn_gateway]
  end

  OYAML --> OCONF --> OSS
  AYAML --> ACONF --> ASS
  OSS <-->|IKEv2 NAT-T UDP 4500| ASS
  OSS --> ONFT
  ASS --> ANFT
```

```mermaid
sequenceDiagram
  participant Admin as OVH admin host
  participant OVH as OVH bastion
  participant AWS as AWS bastion
  participant Jump as AWS jumpbox

  Admin->>OVH: ping -I admin_ip jumpbox
  OVH->>OVH: nft forward + NAT bypass
  OVH->>OVH: policy route table 220
  OVH->>AWS: IPsec ESP (local_ts → remote_ts)
  AWS->>AWS: decrypt, nft forward
  AWS->>Jump: ICMP echo
  Jump-->>Admin: reply via tunnel
```

---

## Configuration Model

### Global settings (`/etc/mycs/config.yml`)

Terraform (`cloud-inceptor/modules/bastion-config`) emits a minimal block:

```yaml
vpn_gateway:
  enabled: yes
  protocol: ipsec
  local_id: test-uk1.ovh.NnovAassist.ai   # bastion FQDN
```

| Key | Purpose |
|-----|---------|
| `enabled` | `yes` runs `configure_vpn_gateway` bootstrap |
| `protocol` | `ipsec` (only supported value) |
| `local_id` | Local IKE identity for all peers |

Additional global IKE/ESP defaults may be present in config or use script defaults (`aes256`, `sha256`, modp2048, etc.).

### Peer settings (`/data/strongswan/peers/<name>.yaml`)

All peer-specific parameters (remote host, CIDRs, direction, auth, CA) live in peer YAML, not Terraform.

---

## Peer YAML Schema

Required keys: `name`, `host`, `local_cidr`, `remote_cidr`, `direction`, `auth`

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Local peer identifier |
| `host` | yes | Remote gateway FQDN or IP (`remote_addrs`) |
| `remote_id` | no | Remote IKE identity (defaults to `host`) |
| `local_cidr` | yes | Local traffic selector (e.g. admin subnet `/26`) |
| `remote_cidr` | yes | Remote traffic selector (peer admin subnet) |
| `remote_peer_vpn_subnet` | no | Remote bastion's road-warrior subnet; required on **ingress** peers for cross-site client access |
| `direction` | yes | `egress`, `ingress`, or `bidirectional` |
| `auth` | yes | `cert` or `psk` |
| `psk` | if auth=psk | Pre-shared key |
| `remote_ca` | if auth=cert | Filename under `/data/strongswan/x509ca/` |
| `remote_ca_pem` | no | Inline PEM staged on `add` |

### Example — OVH egress peer

File: `cloud-inceptor/examples/inceptor/openstack/.UK1/aws-use1-peer.yml`

```yaml
name: aws-us-east-1
host: test-us-east-1.aws.NnovAassist.ai
remote_id: test-us-east-1.aws.NnovAassist.ai
local_cidr: 172.20.64.128/26
remote_cidr: 172.20.9.192/26
direction: egress
auth: cert
remote_ca: aws-root-ca.pem
remote_ca_pem: |
  -----BEGIN CERTIFICATE-----
  ...
  -----END CERTIFICATE-----
```

Egress peers automatically expand `local_ts` to include local road-warrior subnet (`config_vpn_subnet`) when road-warrior VPN is enabled.

### Example — AWS ingress peer

File: `cloud-inceptor/examples/inceptor/aws/.us-east-1/ovh-uk1-peer.yml`

```yaml
name: ovh-uk1
host: test-uk1.ovh.NnovAassist.ai
remote_id: test-uk1.ovh.NnovAassist.ai
local_cidr: 172.20.9.192/26
remote_cidr: 172.20.64.128/26
remote_peer_vpn_subnet: 192.168.111.0/24   # OVH road-warrior subnet
direction: ingress
auth: cert
remote_ca: ovh-root-ca.pem
remote_ca_pem: |
  -----BEGIN CERTIFICATE-----
  ...
  -----END CERTIFICATE-----
```

---

## Scripts and Files

| Script / file | Role |
|---------------|------|
| `configure_vpn_gateway` | Bootstrap: dirs, systemd units, apply existing peers |
| `manage_vpn_gateway_peer` | CLI: add, remove, list, apply |
| `vpn_gateway_common` | Shared library (peer load, swanctl render, nft, NAT bypass) |
| `cloud-inceptor-vpn-gateway-peers.service` | Boot: reload nft, NAT bypass, policy routing |

| Path | Purpose |
|------|---------|
| `/data/strongswan/peers/<name>.yaml` | Peer definitions |
| `/data/strongswan/etc/conf.d/peer-<name>.conf` | Rendered swanctl fragment |
| `/data/strongswan/etc/swanctl.conf` | Includes `conf.d/*` |
| `/data/network/etc/vpn-gateway-peers.nft` | `inet mycs_vpn_gateway` forward rules |
| `/usr/local/etc/.vpn_gateway_installed` | Bootstrap marker |

---

## strongSwan Per-Peer Configuration

Each peer renders to connection `vpn-gateway-<sanitized-name>` with child SA `<name>-net`.

Example fragment (OVH egress):

```
aws-us-east-1-net {
  local_ts = 172.20.64.128/26,192.168.111.0/24
  remote_ts = 172.20.9.192/26
  start_action = start
  ...
}
```

Example fragment (AWS ingress with road-warrior):

```
ovh-uk1-net {
  local_ts = 172.20.9.192/26
  remote_ts = 172.20.64.128/26,192.168.111.0/24
  start_action = none
  ...
}
```

After `manage_vpn_gateway_peer apply`:

```bash
swanctl --load-all
# egress/bidirectional: auto-initiate
swanctl --initiate --child <name>-net --ike vpn-gateway-<name>
```

---

## Traffic Selectors and Directions

`direction` is set **on each bastion** in that bastion's peer YAML. It is not a single property of the link between two sites. When peering Site **A** (e.g. OVH) with Site **B** (e.g. AWS), each side has its own file describing how **it** connects to the other.

The recommended production pairing is **A = `egress`**, **B = `ingress`**. Together they form one site-to-site tunnel with complementary roles: A initiates and may send new flows toward B; B accepts and may receive new flows from A.

Deeper reachability tables and additional flow variants are in [ipsec-vpn-connectivity-design.md](ipsec-vpn-connectivity-design.md).

### How ingress and egress peers work together

Think of the tunnel as two halves that must agree on **traffic selectors** (`local_ts` / `remote_ts`) and **who may start** the CHILD SA:

```mermaid
flowchart TB
  subgraph siteA [Site A — peer direction: egress]
    A_lan[A admin LAN<br/>172.20.64.128/26]
    A_rw[A road-warrior clients<br/>192.168.111.0/24]
    A_bast[Bastion A]
    A_lan --> A_bast
    A_rw --> A_bast
  end

  subgraph siteB [Site B — peer direction: ingress]
    B_bast[Bastion B]
    B_lan[B admin LAN<br/>172.20.9.192/26]
    B_rw[B road-warrior clients<br/>192.168.111.0/24]
    B_bast --> B_lan
    B_rw --> B_bast
  end

  A_bast -->|initiates IKE/CHILD SA<br/>start_action = start| TUN[IPsec tunnel]
  TUN --> B_bast
  B_bast -->|start_action = none<br/>waits for A| TUN

  A_bast -.->|local_ts: A_admin + A_rw| TUN
  TUN -.->|remote_ts on A: B_admin| A_bast
  B_bast -.->|local_ts: B_admin| TUN
  TUN -.->|remote_ts on B: A_admin + A_rw| B_bast
```

| On this bastion | `egress` | `ingress` | `bidirectional` |
|-----------------|----------|-----------|-------------------|
| **IKE `start_action`** | `start` — initiates CHILD SA | `none` — waits for remote | `start` — may initiate |
| **Who brings tunnel up first** | This bastion | Remote bastion | Either side |
| **nftables NEW forward** | Local → remote | Remote → local | Both |
| **`local_ts`** | `local_cidr` + local `vpn.subnet` (if road-warrior enabled) | `local_cidr` only | Same as egress |
| **`remote_ts`** | `remote_cidr` only | `remote_cidr` + `remote_peer_vpn_subnet` | Same as ingress |

**Egress** on A means: A may **start** the tunnel, and **new** flows from A's local networks (admin ± road-warrior) toward B's `remote_cidr` are permitted by nftables and proposed in `local_ts`.

**Ingress** on B means: B **does not** start the tunnel; it accepts IKE from A. **New** flows from B's peer networks (admin ± their road-warrior subnet) toward B's `local_cidr` are permitted and proposed in `remote_ts`.

**Bidirectional** on a bastion combines both: it may initiate **and** accept new flows in both directions for that peer.

### Per-direction behaviour

#### Egress (initiator side)

```mermaid
flowchart LR
  subgraph local [Local networks on egress bastion]
    LAN[local_cidr<br/>admin subnet]
    RW[vpn.subnet<br/>road-warrior pool]
  end

  subgraph bastion [Egress bastion]
    SS[strongSwan<br/>start_action = start]
    NFT[nft mycs_vpn_gateway<br/>NEW: local → remote<br/>RELATED: remote → local]
  end

  subgraph remote [Peer remote networks]
    RLAN[remote_cidr<br/>peer admin subnet]
  end

  LAN --> NFT
  RW --> NFT
  NFT --> SS
  SS -->|ESP local_ts → remote_ts| RLAN
```

- **Initiation:** `manage_vpn_gateway_peer apply` runs `swanctl --initiate` for egress peers.
- **Selectors:** `local_ts` = `local_cidr` (+ local road-warrior subnet when `vpn:` is enabled). `remote_ts` = `remote_cidr` only.
- **Forwarding:** nft allows **new** connections from each egress source CIDR to `remote_cidr`, and **established/related** return traffic from `remote_cidr` back to `local_cidr` (and road-warrior pool for return).

#### Ingress (responder side)

```mermaid
flowchart LR
  subgraph remote [Peer remote networks]
    RLAN[remote_cidr<br/>peer admin subnet]
    RRW[remote_peer_vpn_subnet<br/>peer road-warrior pool]
  end

  subgraph bastion [Ingress bastion]
    SS[strongSwan<br/>start_action = none]
    NFT[nft mycs_vpn_gateway<br/>NEW: remote → local<br/>RELATED: local → remote]
  end

  subgraph local [Local networks on ingress bastion]
    LAN[local_cidr<br/>admin subnet]
  end

  RLAN -->|ESP remote_ts → local_ts| SS
  RRW --> SS
  SS --> NFT
  NFT --> LAN
```

- **Initiation:** does not auto-initiate; waits for the egress (or bidirectional) peer.
- **Selectors:** `local_ts` = `local_cidr` only. `remote_ts` = `remote_cidr` + `remote_peer_vpn_subnet` (when set).
- **Forwarding:** nft allows **new** connections from each remote source CIDR to `local_cidr`, and **established/related** return from `local_cidr` to those remote CIDRs.
- **Important:** ingress does **not** add the **local** road-warrior pool to `local_ts`. Local VPN clients on an ingress-only bastion cannot originate site-to-site flows to the peer without changing direction to `bidirectional` (or `egress`).

#### Bidirectional (either side may initiate)

```mermaid
flowchart TB
  subgraph A [Bidirectional bastion]
    A_src[local_cidr + vpn.subnet]
    A_dst[remote_cidr + remote_peer_vpn_subnet]
    A_nft[nft: NEW both ways<br/>+ established/related both ways]
    A_src <--> A_nft
    A_nft <--> A_dst
  end

  subgraph B [Remote peer]
    B_bast[Remote bastion]
  end

  A_nft <-->|either side may initiate| B_bast
```

- Combines egress initiation with ingress acceptance on the **same** peer entry.
- Use when both sites must initiate tunnels, or when local road-warrior clients on **both** sides need to reach the remote admin LAN.
- Both sides `bidirectional` is valid but may produce duplicate CHILD_SA log lines if both initiate; usually harmless if an SA is already up.

### Paired egress + ingress: end-to-end flows

Example: OVH = **egress**, AWS = **ingress**. Admin subnets `172.20.64.128/26` ↔ `172.20.9.192/26`, shared road-warrior pool `192.168.111.0/24`.

**Deploy order:** apply **ingress** peer on B first (so B's `remote_ts` is ready), then **egress** peer on A (A initiates).

#### Flow 1 — A admin host → B admin host (new connection)

```mermaid
sequenceDiagram
  participant H as Host on A admin LAN
  participant A as Bastion A (egress)
  participant T as IPsec CHILD SA
  participant B as Bastion B (ingress)
  participant J as Host on B admin LAN

  Note over A,B: A initiated tunnel; SA local_ts ⊆ A networks, remote_ts ⊆ B admin

  H->>A: ICMP / TCP (src A_lan, dst B_lan)
  A->>A: nft NEW accept (A_lan → B_admin)
  A->>A: NAT bypass (no DMZ masquerade)
  A->>T: encrypt (src ∈ local_ts, dst ∈ remote_ts)
  T->>B: ESP decrypt
  B->>B: nft NEW accept (A_lan → B_lan)
  B->>J: forward to jumpbox
```

#### Flow 2 — B admin host → A admin host (reverse direction)

Once the CHILD SA is up, B admin hosts can reach A admin hosts. Outbound packets from B use B's `local_ts` (B admin) and A's admin subnet in B's `remote_ts`; return traffic is handled as established/related on both bastions:

```mermaid
sequenceDiagram
  participant J as Host on B admin LAN
  participant B as Bastion B (ingress)
  participant T as IPsec CHILD SA
  participant A as Bastion A (egress)
  participant H as Host on A admin LAN

  J->>B: new flow (src B_lan, dst A_lan)
  B->>B: IPsec policy (src ∈ B local_ts, dst ∈ A admin in remote_ts)
  B->>T: ESP encrypt
  T->>A: decrypt
  A->>A: nft forward to A_lan
  A->>H: deliver
  H-->>J: reply (established/related + IPsec)
```

Admin ↔ admin reachability is **symmetric** with **egress + ingress** as long as the CHILD SA is established (typically admin ↔ admin selectors).

#### Flow 3 — A road-warrior client → B admin host

Requires **both** sides to propose compatible selectors:

| Side | Proposal | Role |
|------|------------|------|
| A (egress) | `local_ts` includes `192.168.111.0/24` | A_rw may send into tunnel |
| B (ingress) | `remote_ts` includes `192.168.111.0/24` | Accept traffic sourced from A_rw |

```mermaid
flowchart LR
  RW[A road-warrior client<br/>192.168.111.x]
  A[Bastion A egress]
  T[Tunnel]
  B[Bastion B ingress]
  J[B admin host]

  RW -->|ikev2-eap-tls decrypt| A
  A -->|local_ts includes A_rw| T
  T -->|remote_ts on B includes A_rw| B
  B --> J
```

If B omits A's road-warrior subnet from `remote_ts`, IKE negotiates **admin-only** selectors even though A's config file lists the VPN pool. Verify with `swanctl --list-sas`, not only the peer conf file.

#### What does not work with egress + ingress alone

| Flow | Works? | Why |
|------|--------|-----|
| B road-warrior → A admin | **No** | B ingress: `local_ts` is admin only; B_rw is not an egress source |
| B road-warrior → A road-warrior | **No** | Same; plus shared `vpn_network` is ambiguous across sites |
| A road-warrior → B road-warrior | **No** | Road-warrior pools not in site-to-site selectors for admin-only SA |

To allow B's road-warrior clients to reach A, set B's peer to `bidirectional` (or `egress`) so B adds its road-warrior pool to `local_ts`.

### Reachability matrix

Assuming **A = egress**, **B = ingress**, tunnel up, routes and NAT bypass correct.

| Source | Destination | Site-to-site | Notes |
|--------|-------------|--------------|-------|
| A admin LAN | B admin LAN | Yes | Primary validated use case |
| B admin LAN | A admin LAN | Yes | Return / reverse new flows via SA + nft |
| A road-warrior | B admin LAN | Sometimes | Needs A_rw in negotiated `local_ts` and B's `remote_ts` |
| B road-warrior | A admin LAN | No | B ingress does not egress B_rw |
| A road-warrior | A admin LAN | Yes | Road-warrior plane (not gateway) |
| A road-warrior | B road-warrior | No | Shared pool / selector limits |

| A direction | B direction | Tunnel comes up? | Symmetric admin reachability |
|-------------|-------------|------------------|------------------------------|
| egress | ingress | A initiates | Yes |
| egress | egress | Both try `start` | Yes if SA establishes |
| ingress | ingress | Neither initiates | **No** |
| bidirectional | bidirectional | Either initiates | Yes |
| egress | bidirectional | Either | Yes |

### Road-warrior cross-site access

For OVH VPN clients to reach AWS admin hosts:

| Side | Selector expansion |
|------|-------------------|
| OVH egress / bidirectional | `local_ts` += `config_vpn_subnet` (automatic) |
| AWS ingress / bidirectional | `remote_ts` += `remote_peer_vpn_subnet` (from peer YAML) |

IKE negotiates the **intersection** of both sides' proposals. If AWS `remote_ts` omits `192.168.111.0/24`, the CHILD SA will not carry road-warrior traffic even if OVH proposes it.

#### Shared road-warrior subnet (`vpn_network`)

Bastions often use the same `vpn_network` (e.g. `192.168.111.0/24`) on each site. If `remote_peer_vpn_subnet` in the peer YAML equals the **local** road-warrior pool, it is **omitted from `remote_ts`** on apply (with a warning). Including it would make the site-to-site CHILD SA claim the local VPN pool in `remote_ts`, so replies to local road-warrior clients (notably DNS to the bastion admin IP) would be encrypted into the peer tunnel instead of returned on the road-warrior SA.

With the omission:

- Local road-warrior DNS and admin reachability keep working after bidirectional peers.
- Cross-site access from local road-warrior clients to **remote admin** hosts still works (`local_ts` still includes the local VPN pool).
- Cross-site **road-warrior-to-road-warrior** traffic is not supported when both sites share the same `vpn_network` (addresses are ambiguous across the tunnel).

---

## nftables and NAT Bypass

### Forward table `inet mycs_vpn_gateway`

Generated by `vpn_gateway_regenerate_nft`. Rules depend on peer `direction` and include road-warrior CIDRs for egress/bidirectional peers.

### NAT bypass (`ip mycs_nat postrouting`)

`vpn_gateway_refresh_nat_bypass` inserts rules with comment `vpn-gateway-nat-bypass` at **chain head** (position 0):

```nft
ip saddr 172.20.64.128/26 ip daddr 172.20.9.192/26 accept comment "vpn-gateway-nat-bypass"
ip saddr 192.168.111.0/24 ip daddr 172.20.9.192/26 accept comment "vpn-gateway-nat-bypass"
```

Without bypass, masquerade on the DMZ interface rewrites source IPs before IPsec policy matching, causing tunnel traffic to fail silently (0 bytes in SA counters).

Verify:

```bash
nft -a list chain ip mycs_nat postrouting | grep vpn-gateway
```

### Docker DOCKER-USER

`vpn_gateway_refresh_docker_user_forward` adds bypass rules for peer local CIDR and road-warrior subnet.

---

## Policy Routing and Admin Routes

### Policy routing (table 220)

strongSwan installs policy routes in table 220. The bastion ensures:

```bash
ip rule add pref 220 from all lookup 220
```

via `vpn_gateway_ensure_policy_routing` on apply and at boot.

Check:

```bash
ip rule list
ip route show table 220
```

### Admin supernet route removal

Cloud providers may install `172.16.0.0/12 via <admin-gateway>` on the admin NIC, stealing routes to peer CIDRs.

Fixes:

1. **Terraform**: when `bastion_as_nat=true`, admin NIC netplan omits the supernet static route.
2. **Runtime**: `vpn_gateway_remove_admin_supernet_routes` deletes conflicting static routes on boot/apply.

Check:

```bash
ip route | grep 172.16
ip route show dev ens4   # admin NIC name varies
```

---

## Runtime Management

```bash
sudo manage_vpn_gateway_peer add /path/to/peer.yaml
sudo manage_vpn_gateway_peer list
sudo manage_vpn_gateway_peer remove <name>
sudo manage_vpn_gateway_peer apply
```

`apply` regenerates all peer conf files, nftables, NAT bypass, Docker rules, reloads swanctl, ensures policy routing, removes admin supernet routes, and **initiates egress/bidirectional peers** (with 1s delay after load).

### apply workflow (vpn_gateway_apply_all)

```
vpn_gateway_regenerate_all_peer_confs
vpn_gateway_regenerate_nft
vpn_gateway_refresh_nat_bypass
vpn_gateway_refresh_docker_user_forward
vpn_gateway_sync_and_load        # swanctl --load-all
vpn_gateway_ensure_policy_routing
vpn_gateway_remove_admin_supernet_routes
vpn_gateway_initiate_egress_peers
```

---

## Multi-Cloud Peering Example (OVH ↔ AWS)

Validated topology:

| | OVH (UK1) | AWS (us-east-1) |
|--|-----------|-----------------|
| Role | egress initiator | ingress responder |
| DMZ IP | 172.20.64.125 | 172.20.8.125 |
| Admin IP | 172.20.64.189 | 172.20.9.253 |
| Admin CIDR | 172.20.64.128/26 | 172.20.9.192/26 |
| Road-warrior | 192.168.111.0/24 | 192.168.111.0/24 |
| Jumpbox | 172.20.64.133 | 172.20.9.249 |

**Deploy order:**

1. Apply AWS ingress peer YAML first (so `remote_ts` includes OVH road-warrior subnet).
2. Apply OVH egress peer YAML (initiates tunnel).
3. Verify both sides: `swanctl --list-sas`

**Reachability tests:**

```bash
# From OVH bastion — use admin source IP
ping -I 172.20.64.189 -c2 172.20.9.249

# From OVH road-warrior client
ping 172.20.9.249
```

---

## Terraform Integration

`cloud-inceptor` provides:

- Minimal `vpn_gateway` block in bastion config (enabled, protocol, local_id)
- `vpn_gateway_peer_cidrs` to bootstrap modules for security group ingress from remote peer admin CIDRs
- Admin NIC netplan fix when `bastion_as_nat=true` (no supernet route)

Peer YAML and `manage_vpn_gateway_peer add` are operational steps after instance launch.

Example peer files:

- `cloud-inceptor/examples/inceptor/openstack/.UK1/aws-use1-peer.yml`
- `cloud-inceptor/examples/inceptor/aws/.us-east-1/ovh-uk1-peer.yml`

---

## Troubleshooting

### Full diagnostic (run as root on each bastion)

```bash
echo "=== $(hostname) $(date -u) ==="

echo "--- strongswan ---"
systemctl is-active strongswan
ls -la /var/run/charon.vici

echo "--- peers ---"
manage_vpn_gateway_peer list
ls -la /data/strongswan/peers/
grep -A6 '\-net' /data/strongswan/etc/conf.d/peer-*.conf

echo "--- swanctl ---"
swanctl --list-conns | grep -E 'vpn-gateway|net:'
swanctl --list-sas
swanctl --list-pols 2>/dev/null | head -20

echo "--- routing ---"
ip route | grep -E '172\.(16|20)|default'
ip rule list
ip route show table 220 2>/dev/null
ip xfrm policy | grep -E '172\.20|192\.168'

echo "--- nft NAT bypass ---"
nft -a list chain ip mycs_nat postrouting | grep -E 'vpn-gateway|172\.|192\.168' | head -10
nft list table inet mycs_vpn_gateway 2>/dev/null | head -30

echo "--- initiate (egress only) ---"
# swanctl --initiate --child <peer>-net --ike vpn-gateway-<peer>
# sleep 2
# swanctl --list-sas

echo "--- reachability ---"
ping -c1 -W2 <local_dmz_ip> >/dev/null && echo "DMZ ok" || echo "DMZ fail"
ping -I <admin_ip> -c2 -W2 <remote_jumpbox_ip>

echo "--- charon log ---"
journalctl -u strongswan -n 40 --no-pager
```

### Issue: swanctl --list-sas empty

| Cause | Resolution |
|-------|------------|
| Not running as root | Use `sudo swanctl --list-sas` |
| Egress peer not initiated | `manage_vpn_gateway_peer apply` or manual `swanctl --initiate` |
| Config not loaded | `swanctl --load-all`; check `journalctl -u strongswan` |
| No peer YAML | `manage_vpn_gateway_peer list` |

### Issue: SA up but 0 bytes/packets

| Cause | Resolution |
|-------|------------|
| NAT masquerade before bypass | `manage_vpn_gateway_peer apply`; verify `vpn-gateway-nat-bypass` at top of postrouting |
| Wrong ping source IP | `ping -I <admin_ip_in_local_ts> ...` |
| Admin supernet route | `ip route show dev <admin_nic>`; apply Terraform fix + `vpn_gateway_remove_admin_supernet_routes` |
| Traffic selector mismatch | Compare `grep local_ts/remote_ts` in peer conf vs `swanctl --list-sas` |

### Issue: admin ping works, road-warrior does not

| Cause | Resolution |
|-------|------------|
| Ingress missing `remote_peer_vpn_subnet` | Add to ingress peer YAML, re-apply on AWS |
| Negotiated SA missing VPN subnet | `swanctl --list-sas` — re-initiate after both sides updated |
| nft forward missing VPN CIDR | `nft list table inet mycs_vpn_gateway` |

### Issue: road-warrior DNS times out after bidirectional peer

| Cause | Resolution |
|-------|------------|
| `remote_ts` included local `vpn_network` via matching `remote_peer_vpn_subnet` | Re-apply peers with current scripts; `remote_peer_vpn_subnet` equal to local pool is auto-omitted from `remote_ts` |
| DNS works on bastion but not VPN client | `dig @<admin_ip> jumpbox.<zone>.local` from client; confirm `swanctl --list-sas` `remote_ts` no longer lists the local VPN pool |

### Issue: CHILD_SA TS narrowed vs config file

Log example:

```
CHILD_SA aws-us-east-1-net{3} established with TS 172.20.64.128/26 === 172.20.9.192/26
```

Config file may show `local_ts = 172.20.64.128/26,192.168.111.0/24` but negotiated SA excludes road-warrior subnet because remote peer did not accept it. Fix remote `remote_ts` / `remote_peer_vpn_subnet` on ingress side.

### Re-apply all gateway config

```bash
sudo manage_vpn_gateway_peer apply
sudo swanctl --list-sas
```

### Re-run bootstrap

```bash
sudo rm -f /usr/local/etc/.vpn_gateway_installed
sudo /usr/local/lib/cloud-inceptor/configure_vpn_gateway 2>&1 | tee /var/log/configure_vpn_gateway.log
```

### Init log

```bash
sudo cat /var/log/configure_vpn_gateway.log
```

---

## Related Documentation

- [network-design.md](network-design.md) — nftables, routing, Docker bypass
- [vpn-design.md](vpn-design.md) — Road-warrior StrongSwan server
- [runtime-bootstrap-design.md](runtime-bootstrap-design.md) — init_instance order
