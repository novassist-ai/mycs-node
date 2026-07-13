# Bastion Road-Warrior VPN Design

This document describes client-to-site VPN on the bastion: OpenVPN, WireGuard, and StrongSwan IKEv2 (IPsec). Site-to-site VPN gateway peers are documented separately in [vpn-gateway-design.md](vpn-gateway-design.md).

---

## Table of Contents

1. [Overview](#overview)
2. [Configuration Model](#configuration-model)
3. [Script Responsibilities](#script-responsibilities)
4. [OpenVPN](#openvpn)
5. [WireGuard](#wireguard)
6. [StrongSwan IKEv2 (Road-Warrior)](#strongswan-ikev2-road-warrior)
7. [Network Integration](#network-integration)
8. [User Management](#user-management)
9. [Idle Shutdown](#idle-shutdown)
10. [Troubleshooting](#troubleshooting)

---

## Overview

Exactly **one** road-warrior VPN type is active, selected by `vpn.type` in `/etc/mycs/config.yml`:

| `vpn.type` | configure script | Client interface |
|------------|------------------|------------------|
| `openvpn` | `configure_openvpn` | `tun0` |
| `wireguard` | `configure_wireguard` | `wg0` |
| `ipsec` | `configure_strongswan` | policy-based (xfrm) |

Each script installs protocol-specific configuration, enables the service, and calls `network_apply_roadwarrior_vpn_nft` to add nftables forwarding and NAT rules documented in [network-design.md](network-design.md#road-warrior-vpn-forwarding). How road-warrior traffic combines with site-to-site peers is in [ipsec-vpn-connectivity-design.md](ipsec-vpn-connectivity-design.md).

Road-warrior VPN and VPN gateway (`vpn_gateway`) are **independent** — both may be enabled simultaneously.

---

## Configuration Model

| Key | Purpose |
|-----|---------|
| `vpn.type` | `openvpn`, `wireguard`, or `ipsec` |
| `vpn.subnet` | Client address pool CIDR (e.g. `192.168.111.0/24`) |
| `vpn.netmask` | Pool netmask |
| `vpn.restricted_subnet` | Restricted routing scope |
| `vpn.tunnel_client_traffic` | Full-tunnel vs split-tunnel |
| `vpn.server_domain` | Internal domain for client configs |
| `vpn.users` | Initial users `user\|password,...` |
| `vpn.openvpn.protocol` | `udp` or `tcp` |
| `vpn.ipsec.support_legacy_clients` | PKCS#12 export mode for Apple clients |
| `vpn.wireguard.*` | Interface name, host IP, subnet |
| `vpn.idle_action` | `shutdown` enables idle disconnect cron |

Certificates for IPsec/OpenVPN are generated from `vpn.vpn_cert_*` fields in config.

---

## Script Responsibilities

| Script | Role |
|--------|------|
| `configure_openvpn` | PKI, `server.conf`, PAM, client profiles |
| `configure_strongswan` | IKEv2 cert-auth server, swanctl layout, user helpers |
| `configure_wireguard` | `wg0` interface, keys, peer tooling |
| `create_openvpn_user` / `create_ipsecvpn_user` | Runtime user creation |
| `delete_*_user` | User removal |
| `idle_shutdown_openvpn` / `idle_shutdown_strongswan` | Idle shutdown hooks |
| `set-wireguard-peer` | Add WireGuard peers |

Service helpers (`strongswan_start_service`, `strongswan_sync_runtime`, etc.) live in `configure_strongswan` and are sourced by `configure_vpn_gateway`.

---

## OpenVPN

### Layout

- PKI under `/data/openvpn/`
- Server config `/etc/openvpn/server.conf`
- Client profiles under `/data/openvpn/clients/`
- Listeners on DMZ interface

### Client routes

`configure_openvpn` pushes routes per LAN subnet in `server.lan_interfaces`. Optional `redirect-gateway` when `tunnel_client_traffic: yes`.

### nftables

Forward and masquerade rules for `iifname "tun0"` — see [network-design.md](network-design.md).

---

## WireGuard

### Layout

- Interface `wg0` (or `vpn.wireguard.itf_name`)
- Server listens on admin or DMZ IP per config
- Peers managed via `set-wireguard-peer`

### nftables

Forward and masquerade rules for `iifname "wg0"`.

---

## StrongSwan IKEv2 (Road-Warrior)

The bastion runs StrongSwan as an IKEv2 VPN server using **swanctl** and **charon-systemd** (Ubuntu 24.04+). Legacy `ipsec.conf`, `ipsec.secrets`, and `/etc/ipsec.d` are **not** used.

### Layout

| Path | Purpose |
|------|---------|
| `/data/strongswan/etc/swanctl.conf` | Main swanctl config (connections, pools, secrets) |
| `/data/strongswan/etc/conf.d/` | Optional fragments (gateway peers) |
| `/data/strongswan/etc/serverinfo` | Variables for user creation scripts |
| `/data/strongswan/{x509ca,x509,private}/` | Persisted credentials |
| `/etc/swanctl/` | Runtime copy synced by `strongswan_sync_runtime` |

Bootstrap marker: `/usr/local/etc/.strongswan_installed`

### Connection `ikev2-eap-tls`

`configure_strongswan` creates:

- IKEv2, NAT-T encapsulation, modern AEAD ciphers
- Server auth: public key (`bastion_cert.pem`)
- Client auth: certificate (pubkey; client certs signed by bastion CA)
- Listens on `server.dmz_itf_ip` (`local_addrs`)
- IKE proposals include `prfsha256/ecp521` for macOS `.mobileconfig` clients
- Virtual IP pool from `vpn.subnet`
- DNS pushed from PowerDNS or config
- Full-tunnel `local_ts = 0.0.0.0/0, ::/0` when configured

After writing config:

```bash
strongswan_sync_runtime   # copy to /etc/swanctl, remove legacy ipsec files
swanctl --load-all
systemctl restart strongswan.service
```

### Packages (installed at build time)

- `charon-systemd`
- `strongswan-swanctl`
- `strongswan-pki`

`strongswan-starter` and the `ipsec` CLI are not used.

### Boot and reload

Stock `strongswan.service` runs `swanctl --load-all --noprompt` in `ExecStartPost`. Bastion dropin `/etc/systemd/system/strongswan.service.d/bastion.conf` extends `TimeoutStartSec`.

---

## Network Integration

After each road-warrior `configure_*` script:

1. `network_apply_vpn_ingress_rules` — INPUT rules for VPN ports on DMZ
2. `network_apply_roadwarrior_routing` — FORWARD and NAT rules
3. `network_nft_save` — persist to `/data/network/etc/nftables.conf`

IPsec additionally applies MSS clamp in `mycs_mangle`.

When `vpn_gateway` is also enabled, egress peers include `vpn.subnet` in `local_ts` and NAT bypass so road-warrior clients can reach remote peer LANs. See [vpn-gateway-design.md](vpn-gateway-design.md).

---

## User Management

### IPsec

```bash
create_vpn_user <user> <password> [ssh_public_key] [legacy|modern]
delete_vpn_user <user>
```

Symlinks: `/usr/local/bin/create_vpn_user` → `create_ipsecvpn_user`

PKCS#12 export modes:

- **legacy** (default) — OpenSSL 1.1 via Docker (`shamelesscookie/openssl:1.1.1s`); required for macOS clients that fail on OpenSSL 3 encrypted PKCS#12
- **modern** — system OpenSSL

Default mode from `vpn.ipsec.support_legacy_clients` in config (`true` → `legacy`).

### Apple `.mobileconfig` profile

`create_ipsecvpn_user` generates IKEv2 profiles validated on macOS:

- Root CA payload: DER-encoded (`bastion_ca.pem`)
- User auth: certificate (`AuthenticationMethod=Certificate`)
- IKE SA: `AES-256-GCM`, DH group 21
- Child SA: `AES-256-GCM`, DH group 21

### OpenVPN / WireGuard

```bash
create_openvpn_user <user> ...
set-wireguard-peer ...
```

---

## Idle Shutdown

When `vpn.idle_action: shutdown`, a cron job runs every minute:

- `idle_shutdown_strongswan` — counts SAs via `swanctl --list-sas`
- `idle_shutdown_openvpn` — OpenVPN session count

Shuts down the instance after `mycs.idle_shutdown_time` minutes with no clients.

---

## Troubleshooting

### StrongSwan service

```bash
sudo systemctl status strongswan
sudo journalctl -u strongswan -n 50 --no-pager
sudo swanctl --list-conns
sudo swanctl --list-sas    # must run as root
ls -la /var/run/charon.vici
```

### Road-warrior vs gateway confusion

| Check | Road-warrior | VPN gateway |
|-------|--------------|-------------|
| Connection name | `ikev2-eap-tls` | `vpn-gateway-<peer>` |
| Config fragment | `swanctl.conf` | `conf.d/peer-*.conf` |
| Peer YAML | N/A | `/data/strongswan/peers/` |

### Client cannot connect (IPsec)

```bash
# On bastion — verify listener and INPUT rules
sudo ss -ulnp | grep -E '500|4500'
sudo nft list chain inet mycs_filter input | grep -E '500|4500'

# Verify cert pool
sudo swanctl --list-pools
sudo ls /data/strongswan/x509/
```

### Client connects but no LAN access

```bash
# Forward rules for ipsec
sudo nft list chain inet mycs_filter forward | grep ipsec
sysctl net.ipv4.ip_forward

# Docker blocking?
sudo iptables -S DOCKER-USER
sudo /usr/local/lib/cloud-inceptor/apply_docker_user_forward
```

### Re-run StrongSwan bootstrap

```bash
sudo rm -f /usr/local/etc/.strongswan_installed
sudo /usr/local/lib/cloud-inceptor/configure_strongswan 2>&1 | tee /var/log/configure_strongswan.log
```

### Hotfix on running bastion

```bash
scp common configure_strongswan create_ipsecvpn_user bastion-admin@host:/tmp/
sudo cp /tmp/common /tmp/configure_strongswan /tmp/create_ipsecvpn_user /usr/local/lib/cloud-inceptor/
sudo ln -sf /usr/local/lib/cloud-inceptor/create_ipsecvpn_user /usr/local/bin/create_vpn_user
sudo rm -f /usr/local/etc/.strongswan_installed
sudo /usr/local/lib/cloud-inceptor/configure_strongswan
```

### Init log

```bash
sudo cat /var/log/configure_strongswan.log
sudo cat /var/log/configure_openvpn.log
sudo cat /var/log/configure_wireguard.log
```

---

## Related Documentation

- [network-design.md](network-design.md) — nftables forwarding for VPN clients
- [vpn-gateway-design.md](vpn-gateway-design.md) — Site-to-site IPsec peers
- [dns-design.md](dns-design.md) — DNS for VPN clients
