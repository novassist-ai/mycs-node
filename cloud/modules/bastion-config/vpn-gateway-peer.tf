#
# Export VPN gateway peer details for this bastion (for use by a remote site).
#

locals {
  vpn_gateway_peer_export_generate = (
    length(var.vpn_gateway_peer_export_path) > 0 && length(var.bastion_admin_subnet_cidr) > 0
  )
  vpn_gateway_peer_export_vpn_subnet = (
    var.vpn_gateway_enabled && var.vpn_type == "ipsec"
    ? var.vpn_network
    : ""
  )
  vpn_gateway_peer_export_dns_server = (
    length(var.bastion_admin_itf_ip) > 0 ? "${var.bastion_admin_itf_ip}:53" : ""
  )
  vpn_gateway_peer_export_local_zone = join(" ", var.vpc_internal_dns_zones)
}

resource "local_file" "vpn_gateway_peer_export" {
  count = local.vpn_gateway_peer_export_generate ? 1 : 0

  content = templatefile("${path.module}/templates/vpn-gateway-peer-export.yml.tpl", {
    peer_name       = var.vpc_name
    peer_host       = var.bastion_fqdn
    admin_cidr      = var.bastion_admin_subnet_cidr
    nat_source      = var.bastion_admin_itf_ip
    dns_server      = local.vpn_gateway_peer_export_dns_server
    local_zone      = local.vpn_gateway_peer_export_local_zone
    peer_vpn_subnet = local.vpn_gateway_peer_export_vpn_subnet
    ca_filename     = "root-ca.pem"
    ca_pem          = chomp(local.root_ca_cert)
  })
  filename = var.vpn_gateway_peer_export_path
}
