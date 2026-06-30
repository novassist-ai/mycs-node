---
# VPN gateway peer export for ${peer_host}
# Provide to a remote site. The remote adds direction, then:
#   sudo manage_vpn_gateway_peer add <peer.yaml>
name: ${peer_name}
host: ${peer_host}
remote_id: ${peer_host}
remote_cidr: ${admin_cidr}
%{if peer_vpn_subnet != "" ~}
remote_peer_vpn_subnet: ${peer_vpn_subnet}
%{endif ~}
auth: cert
remote_ca: ${ca_filename}
remote_ca_pem: |
  ${replace(ca_pem, "\n", "\n  ")}
