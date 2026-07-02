# IPsec VPN Connectivity Design

How traffic moves when a bastion runs **road-warrior VPN** and **VPN gateway** site-to-site IPsec together. Peer schema and NAT semantics: [vpn-gateway-design.md](vpn-gateway-design.md).

---

## Two VPN planes

| Plane | Config | strongSwan | Purpose |
|-------|--------|------------|---------|
| Road-warrior | `vpn:` | `ikev2-eap-tls` | Clients → this bastion |
| VPN gateway | peer YAML | `vpn-gateway-<name>` | This bastion ↔ remote bastion |

---

## Symmetric peering (default)

Both peers: `nat: no`, `remote_nat: no`.

- `local_ts` = local admin + local `vpn.subnet` (if RW enabled)
- `remote_ts` = `remote_cidr` + `remote_peer_vpn_subnet` (with shared-pool guard)
- Both sides initiate (`start_action = start`)
- Admin ↔ admin and RW ↔ remote admin (when selectors negotiate) work both ways

See [vpn-gateway-design.md § Symmetric peering](vpn-gateway-design.md#symmetric-peering-default) for sample YAML and sequence diagrams.

---

## Asymmetric NAT peering (OVH ↔ AWS)

| Bastion | Peer flags | Effect |
|---------|------------|--------|
| OVH | `nat: yes` | SNAT to `nat_source`; `local_ts` = `/32` |
| AWS | `remote_nat: yes`, `remote_nat_source` | `remote_ts` = OVH gateway `/32` only |

OVH → AWS works; AWS → OVH LAN blocked by IPsec selectors. Replies use SNAT conntrack on OVH.

See [vpn-gateway-design.md § Asymmetric NAT peering](vpn-gateway-design.md#asymmetric-nat-peering-ovh--aws).

---

## Road-warrior vs site-to-site

| Topic | Road-warrior | VPN gateway |
|-------|--------------|-------------|
| Child selectors | `0.0.0.0/0` | Per-peer `local_ts` / `remote_ts` |
| nft chain | `mycs_filter` | `mycs_vpn_gateway` |
| NAT | DMZ masquerade | Bypass or peer SNAT |

**Shared `vpn_network`:** if `remote_peer_vpn_subnet` equals the **local** RW pool, it is omitted from `remote_ts` so local RW DNS is not stolen by site-to-site policy.

---

## IKE negotiation

Each side proposes its own selectors; the CHILD SA is the **intersection**. Check `swanctl --list-sas`, not only config files.

---

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Admin works, RW cross-site fails | Negotiated SA; `remote_peer_vpn_subnet` |
| RW DNS timeout | Shared-pool guard; `remote_ts` must not list local `vpn.subnet` |
| SA up, 0 bytes | [vpn-gateway-design.md § nftables](vpn-gateway-design.md#nftables-snat-and-nat-bypass) |

---

## Related documentation

- [vpn-gateway-design.md](vpn-gateway-design.md) — peer YAML, symmetric/asymmetric examples, flows
- [network-design.md](network-design.md) — nft hook order, routing
- [vpn-design.md](vpn-design.md) — road-warrior server
