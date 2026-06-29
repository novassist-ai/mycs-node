# Bastion Network Design

This document describes how the bastion appliance routes traffic: interface layout, **nftables** packet filtering, road-warrior VPN forwarding, optional **VPN gateway** (site-to-site IPsec), Docker `DOCKER-USER` bypass, and operational troubleshooting.

Runtime configuration is delivered as `/etc/mycs/config.yml` by Terraform (`cloud-inceptor/modules/bastion-config`).

---

## Table of Contents

1. [Overview](#overview)
2. [Configuration Model](#configuration-model)
3. [Bootstrap and Script Responsibilities](#bootstrap-and-script-responsibilities)
4. [Interface Layout](#interface-layout)
5. [Base Router Behaviour](#base-router-behaviour)
6. [Road-Warrior VPN Forwarding](#road-warrior-vpn-forwarding)
7. [VPN Gateway Forwarding](#vpn-gateway-forwarding)
8. [Combined Topologies](#combined-topologies)
9. [nftables Rule Reference](#nftables-rule-reference)
10. [Packet Flow Diagrams](#packet-flow-diagrams)
11. [Persistence and Boot](#persistence-and-boot)
12. [Docker DOCKER-USER Forward Bypass](#docker-docker-user-forward-bypass)
13. [Terraform Integration](#terraform-integration)
14. [Troubleshooting](#troubleshooting)
15. [Operational Notes](#operational-notes)

---

## Overview

The bastion is a **Linux router** with one or more Ethernet interfaces:

| Role | Typical interface | Purpose |
|------|-------------------|---------|
| DMZ / NAT | First NIC (`eth0`, `ens3`, `ens5`, …) | Public or edge-facing; default route to the Internet |
| Admin / internal LAN | Second NIC (optional) | VPC or private network segments |

At first boot, `configure_network` applies netplan, enables IP forwarding, and installs **LAN** nftables forwarding and NAT rules. Road-warrior and VPN-gateway rules are added by each `configure_*` VPN script after its service is configured.

Road-warrior VPN and VPN gateway are **orthogonal**:

- **`vpn`** — how remote users connect *to* the bastion (exactly one of wireguard, openvpn, or ipsec).
- **`vpn_gateway`** — how the bastion connects *out* to upstream IPsec peers (site-to-site).

Either section may be omitted from `config.yml`.

```mermaid
flowchart TB
  subgraph clients [Road warriors]
    RW[VPN clients]
  end

  subgraph bastion [Bastion router]
    NET[configure_network<br/>nftables + forwarding]
    RWVPN[configure_openvpn /<br/>configure_strongswan /<br/>configure_wireguard]
    GW[configure_vpn_gateway<br/>upstream IPsec conn]
  end

  subgraph internal [Internal networks]
    LAN[LAN hosts]
  end

  subgraph external [External]
    INET[Internet]
    UPGW[Upstream VPN gateway]
    REMOTE[Remote CIDR behind gateway]
  end

  RW -->|road-warrior VPN| RWVPN
  RWVPN --> NET
  LAN --> NET
  NET --> INET
  NET --> LAN
  GW --> UPGW
  UPGW --> REMOTE
  NET -->|transit| GW
```

For road-warrior VPN configuration details see [vpn-design.md](vpn-design.md). For site-to-site gateway peers see [vpn-gateway-design.md](vpn-gateway-design.md).

---

## Configuration Model

YAML is parsed by `scripts/config/common` (`parse_yaml`) into bash variables prefixed with `config_`. Nested keys use underscores (e.g. `vpn_gateway.protocol` → `config_vpn_gateway_protocol`).

### Optional defaults

| Variable | Default |
|----------|---------|
| `config_vpn_type` | *(empty — no road-warrior VPN)* |
| `config_vpn_subnet` | *(empty)* |
| `config_vpn_gateway_enabled` | `no` |
| `config_vpn_gateway_protocol` | `ipsec` |

### `server.lan_interfaces`

Comma-separated NIC descriptors. Each entry uses pipe-separated fields:

```
private_ip|interface_cidr|static_route_cidr|gateway|dhcp_start|dhcp_end
```

| Field | Meaning |
|-------|---------|
| `private_ip` | Static IP, DHCP (`""`), or disable (`x`) |
| `interface_cidr` | Subnet on this link (e.g. `172.20.64.128/26`) |
| `static_route_cidr` | Route installed on this interface (often `0.0.0.0/0` on DMZ) |
| `gateway` | Next hop for static route |
| `dhcp_*` | Optional DHCP range served by bastion |

The **first** entry is always the DMZ/NAT interface.

When `bastion_as_nat` is enabled in Terraform, the admin NIC static route for `global_internal_cidr` (e.g. `172.16.0.0/12`) is **cleared** in netplan to prevent a cloud-provisioned supernet route from stealing traffic destined for VPN peer CIDRs. At runtime, `vpn_gateway_remove_admin_supernet_routes` in `vpn_gateway_common` deletes any remaining conflicting static routes on the admin interface.

### `vpn_gateway` (global defaults)

`vpn_gateway` in `/etc/mycs/config.yml` supplies **global** strongSwan defaults. Individual peers are defined in `/data/strongswan/peers/<name>.yaml` and managed with `manage_vpn_gateway_peer`.

| Key | Purpose |
|-----|---------|
| `enabled` | `yes` runs `configure_vpn_gateway` bootstrap |
| `protocol` | `ipsec` (only supported value today) |
| `local_id` | Local IKE identity (typically bastion FQDN) |

---

## Bootstrap and Script Responsibilities

| Script | Responsibility |
|--------|----------------|
| `configure_network` | netplan, sysctl, **LAN nftables** (no VPN rules) |
| `configure_openvpn` / `configure_strongswan` / `configure_wireguard` | Protocol setup + **road-warrior nft rules** |
| `configure_vpn_gateway` | Gateway bootstrap; peer swanctl + **VPN gateway nft rules** |
| `manage_vpn_gateway_peer` | Runtime peer add/remove/list/apply |

Shared routing helpers live in **`common`** (`network_*` functions).

`init_instance` order:

```
mount_volume
configure_network        ← netplan, sysctl, LAN nftables
configure_users / apache / docker
configure_powerdns
configure_smtp / openvpn / strongswan / wireguard / vpn_gateway / ...
```

When `init_instance` exits, it writes `/var/log/network-configuration.dump` via `network_configuration_dump` in `network_dump`.

---

## Interface Layout

```mermaid
flowchart LR
  INET[Internet / VPC edge]

  subgraph bastion [Bastion]
    DMZ[DMZ NIC<br/>config_server_dmz_itf_ip]
    ADM[Admin NIC<br/>config_server_admin_itf_ip]
  end

  LAN[Internal LAN<br/>VPC CIDR / global_internal_cidr]

  INET <--> DMZ
  ADM <--> LAN
```

- **DMZ**: VPN listeners bind here; NAT to the Internet uses this interface as `-o $public_itf`.
- **Admin/LAN**: Internal workloads; IKE often uses DMZ public IP with NAT-T.

Static interfaces set `dhcp4: false` and `dhcp6: false` so cloud-init's ephemeral DHCP does not compete with systemd-networkd on secondary ENIs. When a `static_route_cidr` is configured, the address uses the interface subnet prefix (e.g. `/26`) rather than `/32` so connected routes apply reliably at boot.

---

## Base Router Behaviour

Applied by `configure_network`. VPN-specific nftables are added later by each `configure_*` VPN script.

### sysctl

- `net.ipv4.ip_forward=1`
- ICMP redirects disabled; `rp_filter=2` (loose)

### nftables tables

Created by `network_nft_init` in `common`:

| Table | Family | Chain | Hook |
|-------|--------|-------|------|
| `mycs_filter` | `inet` | `input` | input (filter) |
| `mycs_filter` | `inet` | `forward` | forward (filter) |
| `mycs_nat` | `ip` | `postrouting` | postrouting (srcnat) |
| `mycs_mangle` | `ip` | `forward` | forward (mangle) |

Base rules:

1. **input**: `ct state established,related accept`; `iif lo accept`; `ct state invalid drop`
2. **forward**: `ct state established,related accept` (inserted at chain head)
3. **Per LAN subnet**: `masquerade` on DMZ; forward NEW to Internet and peer LANs

Example LAN masquerade:

```nft
insert rule ip mycs_nat postrouting oifname "ens3" ip saddr 172.20.64.128/26 masquerade
insert rule inet mycs_filter forward iifname "ens4" oifname "ens3" ip saddr 172.20.64.128/26 ct state new accept
```

---

## Road-Warrior VPN Forwarding

Configured when `vpn.type` and `vpn.subnet` are set. Routing is applied in `network_apply_roadwarrior_routing()` from the active VPN `configure_*` script via `network_apply_roadwarrior_vpn_nft`.

### Ingress (`network_apply_vpn_ingress_rules`)

| Type | INPUT rule |
|------|------------|
| OpenVPN | `iifname $dmz $protocol dport $port accept` |
| WireGuard | `iifname $dmz udp dport $port accept` |
| IPsec | `udp dport { 500, 4500 } accept` |

### Egress and forwarding

| Type | Match | Internet | Internal LAN |
|------|-------|----------|--------------|
| OpenVPN | `iifname "tun0"` | forward to DMZ + `masquerade` | forward `tun0` → LAN |
| WireGuard | `iifname "wg0"` | forward to DMZ + `masquerade` | forward `wg0` → LAN |
| IPsec | `ipsec in/out ip saddr/daddr` | `masquerade` + IPsec policy rules | forward DMZ → LAN |

IPsec MSS clamp (`mycs_mangle`):

```nft
add rule ip mycs_mangle forward ipsec in ip saddr $vpn_subnet oifname $dmz \
  tcp flags syn,rst tcp option maxseg size 1361-1536 tcp option maxseg size set 1360
```

See [vpn-design.md](vpn-design.md) for server configuration.

---

## VPN Gateway Forwarding

When `vpn_gateway.enabled: yes` or peer YAML exists under `/data/strongswan/peers/`, forward policy is managed in table `inet mycs_vpn_gateway` (`/data/network/etc/vpn-gateway-peers.nft`).

Peer forward rules are generated by `vpn_gateway_regenerate_nft` in `vpn_gateway_common`. NAT bypass rules in `ip mycs_nat postrouting` prevent masquerade from breaking IPsec traffic selectors.

For egress/bidirectional peers, road-warrior subnet (`config_vpn_subnet`) is included in NAT bypass and forward rules alongside `local_cidr`.

See [vpn-gateway-design.md](vpn-gateway-design.md) for peer model, traffic selectors, and troubleshooting.

---

## Combined Topologies

### A — Router only

No `vpn` or `vpn_gateway` sections. Base LAN ↔ Internet forwarding only.

### B — Road-warrior only

```yaml
vpn:
  type: ipsec   # or openvpn / wireguard
  subnet: 192.168.111.0/24
```

### C — VPN gateway only

```yaml
vpn_gateway:
  enabled: yes
  protocol: ipsec
```

Peers added at runtime with `manage_vpn_gateway_peer add`.

### D — Road-warrior + VPN gateway

Both sections present. Road warriors and LAN hosts can reach remote peer CIDRs when peers, traffic selectors, and cloud routes are configured.

---

## nftables Rule Reference

Rule generation order:

```
1. network_nft_init (configure_network)
2. LAN loop in configure_network — masquerade + inter-LAN forward
3. network_nft_save (configure_network)
4. network_apply_roadwarrior_vpn_nft (configure_openvpn / strongswan / wireguard)
5. vpn_gateway_regenerate_nft (configure_vpn_gateway / manage_vpn_gateway_peer)
6. network_nft_save after each VPN script
```

`rc.local` loads `/data/network/etc/nftables.conf` on every boot with `nft -f`.

VPN gateway NAT bypass uses comment `vpn-gateway-nat-bypass` and is inserted at **position 0** in `ip mycs_nat postrouting` so it precedes LAN masquerade rules.

---

## Packet Flow Diagrams

### LAN host → upstream remote CIDR (site-to-site)

```mermaid
sequenceDiagram
  participant H as LAN host
  participant B as Bastion
  participant S as strongSwan
  participant U as Upstream gateway
  participant R as Remote network

  H->>B: dst in remote_cidr
  Note over H,B: VPC route: remote_cidr → bastion
  B->>B: FORWARD ACCEPT src=LAN dst=remote
  B->>S: Policy match local_ts/remote_ts
  S->>U: IPsec ESP
  U->>R: Plaintext to remote LAN
```

### Road-warrior → upstream remote CIDR

```mermaid
flowchart LR
  RW[Road warrior] -->|VPN tunnel| B[Bastion decrypt]
  B -->|forward src=vpn_subnet dst=remote_cidr| F[nftables]
  F -->|NAT bypass no MASQ| S[strongSwan encrypt]
  S --> U[Upstream gateway]
  U --> R[Remote CIDR]
```

---

## Persistence and Boot

| Path | Purpose |
|------|---------|
| `/data/network/etc/nftables.conf` | Saved `mycs_filter`, `mycs_nat`, `mycs_mangle` tables |
| `/etc/netplan/99-bastion-network-config.yaml` | Interface configuration |
| `/data/network/etc/vpn-gateway-peers.nft` | VPN gateway forward table (loaded by systemd) |

On every boot:

- `rc.local` → `nft -f /data/network/etc/nftables.conf`
- `cloud-inceptor-vpn-gateway-peers.service` → reload gateway nft, NAT bypass, policy routing, remove admin supernet routes

Stock `nftables.service` is disabled at image build time.

---

## Docker DOCKER-USER Forward Bypass

Docker installs an `ip filter FORWARD` chain with **policy DROP** and an empty **`DOCKER-USER`** chain when `dockerd` starts. Bastion VPN rules live in **`inet mycs_filter`** (policy accept). After reboot, Docker may register before `rc.local` reloads nftables, dropping forwarded VPN traffic unless `DOCKER-USER` allows it.

`configure_docker` installs:

| Component | Purpose |
|-----------|---------|
| `apply_docker_user_forward` | Idempotently inserts `ACCEPT` in `DOCKER-USER` per forward CIDR |
| `docker.service.d/cloud-inceptor-forward.conf` | `ExecStartPost` re-applies rules on every `dockerd` start |
| `cloud-inceptor-docker-forward.service` | Oneshot applies rules after Docker on boot |

CIDRs from `network_collect_docker_user_forward_cidrs`: road-warrior subnet, LAN prefixes, VPN gateway transit sources.

---

## Terraform Integration

`cloud-inceptor/modules/bastion-config/bastion.tf` emits `vpn_gateway:` with:

| Terraform variable | YAML key |
|--------------------|----------|
| `vpn_gateway_enabled` | `vpn_gateway.enabled` |
| `vpn_gateway_protocol` | `vpn_gateway.protocol` |
| *(derived)* | `vpn_gateway.local_id` ← bastion FQDN |

Peer-specific settings (remote host, CIDRs, CA PEMs) are **not** in Terraform; they are managed via peer YAML at runtime.

Bootstrap modules pass `vpn_gateway_peer_cidrs` for security group rules allowing ingress from remote peer admin CIDRs.

For LAN reachability to `remote_cidr`, add VPC routes pointing at the bastion instance.

---

## Troubleshooting

### Health check script (run as root)

Use this consolidated check on either bastion when diagnosing site-to-site connectivity:

```bash
echo "=== $(hostname) $(date -u) ==="

echo "--- strongswan ---"
systemctl is-active strongswan
ls -la /var/run/charon.vici

echo "--- peers ---"
manage_vpn_gateway_peer list
grep -E 'local_ts|remote_ts' /data/strongswan/etc/conf.d/peer-*.conf

echo "--- swanctl ---"
swanctl --list-conns | grep -E 'vpn-gateway|net:'
swanctl --list-sas

echo "--- routing ---"
ip route | grep -E '172\.(16|20)|default'
ip rule list
ip route show table 220 2>/dev/null

echo "--- nft NAT bypass ---"
nft -a list chain ip mycs_nat postrouting | grep -E 'vpn-gateway|172\.|192\.168' | head -15
nft list table inet mycs_vpn_gateway 2>/dev/null | head -30

echo "--- reachability ---"
ping -c1 -W2 <local_dmz_ip> >/dev/null && echo "DMZ ok" || echo "DMZ fail"
ping -I <admin_ip> -c2 -W2 <remote_jumpbox_ip>

echo "--- charon log ---"
journalctl -u strongswan -n 40 --no-pager
```

Run `swanctl` as **root** — non-root users get `Permission denied` on `/var/run/charon.vici`.

### Ping fails with "Destination Host Unreachable" to remote LAN

**Symptom:** Tunnel appears configured but ping from bastion admin subnet to remote jumpbox fails; `swanctl --list-sas` may show 0 bytes/packets.

**Causes and fixes validated in OVH ↔ AWS testing:**

1. **Wrong source IP** — Ping from DMZ IP when traffic selectors only include admin subnet.
   ```bash
   # Use admin interface IP explicitly
   ping -I 172.20.64.189 -c2 172.20.9.249
   ```

2. **Conflicting admin supernet route** — OpenStack/AWS may install `172.16.0.0/12 via <admin-gateway> dev <admin-nic>`, intercepting traffic to remote peer CIDRs.
   ```bash
   ip route show dev ens4   # admin NIC
   # Fix: Terraform clears static route when bastion_as_nat=true
   # Runtime: manage_vpn_gateway_peer apply runs vpn_gateway_remove_admin_supernet_routes
   ```

3. **NAT masquerade before VPN bypass** — Traffic masqueraded before IPsec policy match.
   ```bash
   nft -a list chain ip mycs_nat postrouting | head -20
   # vpn-gateway-nat-bypass rules must appear BEFORE masquerade rules
   sudo manage_vpn_gateway_peer apply
   ```

4. **Policy routing not active**
   ```bash
   ip rule list | grep 220
   # Should show: 220: from all lookup 220
   ```

### swanctl --list-sas empty after apply

**Symptom:** No IKE/CHILD SAs after `manage_vpn_gateway_peer apply`.

**Causes:**

- Egress peer not initiated (AWS ingress waits; OVH egress must initiate).
- `swanctl --initiate` failed silently (now logs WARNING).

**Fix:**

```bash
# On egress side (e.g. OVH)
swanctl --initiate --child aws-us-east-1-net --ike vpn-gateway-aws-us-east-1
swanctl --list-sas

# Or re-apply (auto-initiates egress/bidirectional peers)
sudo manage_vpn_gateway_peer apply
```

### Road-warrior clients cannot reach remote peer LAN

**Symptom:** Bastion admin subnet ping works; VPN clients cannot.

**Cause:** Traffic selector mismatch — egress `local_ts` includes road-warrior subnet but ingress `remote_ts` does not include remote peer's road-warrior subnet.

**Fix:** On the **ingress** peer YAML, set:

```yaml
remote_peer_vpn_subnet: 192.168.111.0/24
```

Then `manage_vpn_gateway_peer apply` on both sides. Verify negotiated SA:

```bash
swanctl --list-sas | grep -E 'local|remote'
```

### Docker blocking forwarded traffic after reboot

```bash
iptables -S DOCKER-USER
sudo /usr/local/lib/cloud-inceptor/apply_docker_user_forward
```

### Full network dump

```bash
sudo /usr/local/lib/cloud-inceptor/network_dump /tmp/netdump.txt success
less /tmp/netdump.txt
cat /var/log/network-configuration.dump
```

### Init / configure_network logs

```bash
sudo tail -100 /var/log/configure_network.log
sudo nft list ruleset | less
ip -4 addr; ip route; ip rule list
```

---

## Operational Notes

1. **Overlapping CIDRs** — Avoid overlap between `vpn.subnet`, LAN subnets, and peer `remote_cidr`.
2. **strongSwan unit** — Ubuntu 24.04+ uses `strongswan.service` with `swanctl`; legacy `ipsec.conf` is not used.
3. **Re-running scripts** — Marker files under `/usr/local/etc/.{service}_installed` prevent duplicate configuration.
4. **nftables only** — Tables `mycs_filter`, `mycs_nat`, `mycs_mangle`; IPsec rules require kernel xfrm/`ipsec` expression support.
5. **Agent plugin warnings** — `agent plugin requires CAP_SETUID` from `swanctl` as non-root is harmless; always run diagnostics as root.

---

## Related Documentation

- [vpn-design.md](vpn-design.md) — Road-warrior VPN (OpenVPN, WireGuard, IKEv2)
- [vpn-gateway-design.md](vpn-gateway-design.md) — Site-to-site peers and peering
- [dns-design.md](dns-design.md) — Internal DNS
- [runtime-bootstrap-design.md](runtime-bootstrap-design.md) — First-boot orchestration
