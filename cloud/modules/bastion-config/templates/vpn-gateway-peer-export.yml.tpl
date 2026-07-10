---
# VPN gateway peer export for ${peer_host}
# Provide to a remote site. Uncomment/adjust NAT fields as needed, then:
#   sudo manage_vpn_gateway_peer add <peer.yaml>
name: ${peer_name}
host: ${peer_host}
remote_id: ${peer_host}
remote_cidr: ${admin_cidr}
%{if peer_vpn_subnet != "" ~}
remote_peer_vpn_subnet: ${peer_vpn_subnet}
%{endif ~}
auth: cert
#
# On THIS site (exporter): vpn_gateway.nat in /etc/mycs/config.yml is the default.
#   nat: yes|no  — uncomment to override the global value for this peer only.
#   nat_source:  — defaults to the bastion admin interface; set only if this peer
#     should SNAT via a different interface or IP.
# On the RECEIVING site: uncomment remote_nat: yes when this remote peer uses NAT.
#   remote_nat_source is set from this export (this bastion's gateway admin IP).
# remote_dns_server and remote_local_zone configure DNSDist to forward this peer's
#   zone(s) to the remote DNS. remote_dns_server may list primary,backup (comma/
#   space-separated) for firstAvailable failover.
#
# nat:
# nat_source:
# remote_nat: yes
# remote_nat_source: ${nat_source}
%{if dns_server != "" && local_zone != "" ~}
remote_dns_server: ${dns_server}
remote_local_zone: ${local_zone}
%{endif ~}
remote_ca: ${ca_filename}
remote_ca_pem: |
  ${replace(ca_pem, "\n", "\n  ")}
