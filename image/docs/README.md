# Bastion Image Design Documentation

Index of design documents for the `mycs-node/image` module.

---

## Build and Bootstrap

| Document | Topics |
|----------|--------|
| [build-design.md](build-design.md) | Packer, build scripts, `install_packages`, Docker build env, GitHub Actions |
| [runtime-bootstrap-design.md](runtime-bootstrap-design.md) | `init_instance`, configure script order, markers, first-boot troubleshooting |

## Runtime Subsystems

| Document | Topics |
|----------|--------|
| [network-design.md](network-design.md) | netplan, nftables, NAT, forwarding, Docker bypass, network troubleshooting |
| [dns-design.md](dns-design.md) | PowerDNS, DNSDist, Pi-hole, internal zones |
| [vpn-design.md](vpn-design.md) | OpenVPN, WireGuard, StrongSwan IKEv2 road-warrior |
| [vpn-gateway-design.md](vpn-gateway-design.md) | Site-to-site IPsec peers, OVH↔AWS peering, gateway troubleshooting |

## Supplementary

| Document | Topics |
|----------|--------|
| [build.md](build.md) | Legacy YAML schema (OpenVPN, Squid, Concourse) |
| [git-crypt.md](git-crypt.md) | git-crypt key injection |

---

Return to [README.md](../README.md).
