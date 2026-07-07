# Runtime Bootstrap Design

This document describes how a bastion instance is configured on **first boot** after Terraform in [`cloud-inceptor`](https://github.com/novassist-ai/mycs-node.git/cloud) launches it with cloud-init user-data.

---

## Table of Contents

1. [Overview](#overview)
2. [Configuration Delivery](#configuration-delivery)
3. [init_instance Orchestration](#init_instance-orchestration)
4. [Configure Scripts Reference](#configure-scripts-reference)
5. [Idempotency and Markers](#idempotency-and-markers)
6. [Boot Hook — rc.local](#boot-hook--rclocal)
7. [Network Configuration Dump](#network-configuration-dump)
8. [Troubleshooting First Boot](#troubleshooting-first-boot)

---

## Overview

The image built by Packer contains packages and scripts but **no environment-specific settings**. At launch, `cloud-inceptor` delivers:

- Admin SSH key and user
- TLS certificates
- MyCloudSpace node private key
- Gzip/base64-encoded `bastion-config.yml`

`init_instance` converts this into live services on the bastion.

```mermaid
flowchart TB
  TF[cloud-inceptor Terraform] --> CI[cloud-init user-data]
  CI --> BC[/usr/local/etc/bastion-config.yml]
  CI --> INIT[init_instance]
  BC --> INIT
  INIT --> MV[mount_volume]
  MV --> NET[configure_network]
  NET --> USR[configure_users]
  USR --> WEB[configure_apache]
  WEB --> DOC[configure_docker]
  DOC --> DNS[configure_powerdns]
  DNS --> SMTP[configure_smtp]
  SMTP --> OVPN[configure_openvpn]
  OVPN --> SS[configure_strongswan]
  SS --> WG[configure_wireguard]
  WG --> GW[configure_vpn_gateway]
  GW --> SQ[configure_squidproxy]
  SQ --> NODE[configure_mycsnode]
```

---

## Configuration Delivery

| Path | Purpose |
|------|---------|
| `/usr/local/etc/bastion-config.yml` | Delivered by cloud-init; moved to `/etc/mycs/config.yml` |
| `/etc/mycs/config.yml` | Canonical runtime config (owned by `mycs`, mode `0600`) |
| `/etc/ssl/certs/bastion_ca.pem` | Bastion TLS CA; copied to `/etc/mycs/local-ca-root.pem` |

If `/etc/mycs/config.yml` is absent, individual `configure_*` scripts may read EC2-compatible user-data from `169.254.169.254` via helpers in `common`.

YAML is parsed by `parse_yaml` in `scripts/config/common` into bash variables prefixed with `config_`.

---

## init_instance Orchestration

Script: `scripts/config/init_instance`

1. Waits up to 300s for cloud-init boot-finished marker.
2. Moves `bastion-config.yml` → `/etc/mycs/config.yml`.
3. Creates log files under `/var/log/configure_*.log` (mode `0600`).
4. Runs each `configure_*` script sequentially via `run_config_script`:
   - stdout/stderr tee'd to `/var/log/{script}.log`
   - Failures set `init_failed=true` but later scripts still run
5. On exit (success or failure), writes `/var/log/network-configuration.dump` via `network_configuration_dump`.
6. Creates `/usr/local/etc/.init_instance_complete` on success.

**Execution order** (fixed):

```
mount_volume
configure_network
configure_users
configure_apache
configure_docker
configure_powerdns
configure_smtp
configure_openvpn
configure_strongswan
configure_wireguard
configure_vpn_gateway
configure_squidproxy
configure_mycsnode
```

`configure_network` must run before VPN and DNS scripts because later scripts depend on interface IPs, nftables base tables, and forwarding being enabled.

---

## Configure Scripts Reference

| Script | Marker file | Design doc |
|--------|-------------|------------|
| `mount_volume` | — | *(this document)* |
| `configure_network` | `.network_installed` | [network-design.md](network-design.md) |
| `configure_users` | `.users_installed` | — |
| `configure_apache` | `.apache_installed` | — |
| `configure_docker` | `.docker_installed` | — |
| `configure_powerdns` | `.powerdns_installed` | [dns-design.md](dns-design.md) |
| `configure_smtp` | `.smtp_installed` | — |
| `configure_openvpn` | `.openvpn_installed` | [vpn-design.md](vpn-design.md) |
| `configure_strongswan` | `.strongswan_installed` | [vpn-design.md](vpn-design.md) |
| `configure_wireguard` | `.wireguard_installed` | [vpn-design.md](vpn-design.md) |
| `configure_vpn_gateway` | `.vpn_gateway_installed` | [vpn-gateway-design.md](vpn-gateway-design.md) |
| `configure_squidproxy` | `.squidproxy_installed` | — |
| `configure_mycsnode` | `.mycsnode_installed` | — |

### mount_volume

Attaches and mounts the data volume defined in `config.yml` (`data.attached_device_name`, `data.mount_directory`, default `/data`). StrongSwan peer YAML, nftables persistence, and Docker data rely on this volume.

### configure_users

Creates the admin user, SSH keys, and passwords from `server.admin_*` config keys.

### configure_apache

HTTPS admin API, static content from `/var/www/html`, external authentication via pwauth.

### configure_docker

Enables Docker, loads saved Pi-hole and OpenSSL images, installs `DOCKER-USER` forward bypass via `apply_docker_user_forward` and systemd drop-ins, and registers `cloud-inceptor-docker-pihole.service` for boot. Re-running `configure_docker` on an already-configured host refreshes boot units only. See [network-design.md](network-design.md#docker-docker-user-forward-bypass).

### configure_smtp

Postfix relay using SendGrid or configured SMTP relay from `smtp.*` config.

### configure_squidproxy

Optional HTTP proxy when `squidproxy` section is present in config.

### configure_mycsnode

Enables `mycs-node`, `mycs-daemon`, and `tailscaled` systemd services.

---

## Idempotency and Markers

Each `configure_*` script checks `/usr/local/etc/.{service}_installed` and exits immediately if present. To re-run a script after config changes:

```bash
sudo rm -f /usr/local/etc/.strongswan_installed
sudo /usr/local/lib/cloud-inceptor/configure_strongswan
```

---

## Boot Hook — rc.local

**cloud-init user-data runs once** on first boot; marker files prevent `configure_*` scripts from re-running on reboot.

`scripts/config/rc.local` runs on **every boot**:

1. `network_apply_boot_network` — `nft -f /data/network/etc/nftables.conf`, `sysctl -p /etc/sysctl.conf`, refresh `DOCKER-USER` if `dockerd` is already running
2. Ensure `/var/run/mycs` permissions
3. Re-run `configure_apache` if Apache is installed

`cloud-inceptor-docker-pihole.service` starts `dockerd` and Pi-Hole **after** `rc-local.service` so nftables masquerade/forward rules exist before Docker's `FORWARD` DROP policy is applied. `boot_docker_pihole` applies `DOCKER-USER` bypass rules last (Pi-Hole compose can recreate Docker iptables chains).

VPN gateway peer nftables and NAT bypass are handled by `cloud-inceptor-vpn-gateway-peers.service` (installed by `configure_vpn_gateway`). Cross-site DNSDist peer backends are refreshed on boot by `cloud-inceptor-vpn-gateway-dnsdist.service` (after strongSwan and dnsdist; also re-initiates peers). Docker `DOCKER-USER` bypass is also refreshed by `cloud-inceptor-docker-forward.service` and `docker.service` `ExecStartPost`.

---

## Network Configuration Dump

On `init_instance` exit, `network_dump` writes a diagnostic snapshot to `/var/log/network-configuration.dump` including:

- Parsed config summary
- `ip addr`, routes, rules
- nftables rulesets
- strongSwan / swanctl status (when installed)

Use this file for post-mortem analysis when first boot fails.

---

## Troubleshooting First Boot

### Check init progress

```bash
sudo tail -f /var/log/init_instance.log
sudo ls -la /var/log/configure_*.log
sudo cat /var/log/configure_network.log
```

### Verify init completed

```bash
test -f /usr/local/etc/.init_instance_complete && echo OK || echo INCOMPLETE
```

### Re-run a single configure script

```bash
sudo rm -f /usr/local/etc/.network_installed
sudo /usr/local/lib/cloud-inceptor/configure_network 2>&1 | tee /var/log/configure_network.log
```

### Full network diagnostic dump

```bash
sudo /usr/local/lib/cloud-inceptor/network_dump /tmp/dump.txt success
less /tmp/dump.txt
```

---

## Related Documentation

- [build-design.md](build-design.md) — Image build process
- [network-design.md](network-design.md) — Network subsystem
- [dns-design.md](dns-design.md) — DNS subsystem
- [vpn-design.md](vpn-design.md) — Road-warrior VPN
- [vpn-gateway-design.md](vpn-gateway-design.md) — Site-to-site VPN gateway
