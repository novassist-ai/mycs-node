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
}

resource "local_file" "vpn_gateway_peer_export" {
  count = local.vpn_gateway_peer_export_generate ? 1 : 0

  content = templatefile("${path.module}/templates/vpn-gateway-peer-export.yml.tpl", {
    peer_name       = var.vpc_name
    peer_host       = var.bastion_fqdn
    admin_cidr      = var.bastion_admin_subnet_cidr
    peer_vpn_subnet = local.vpn_gateway_peer_export_vpn_subnet
    ca_filename     = "root-ca.pem"
    ca_pem          = chomp(local.root_ca_cert)
  })
  filename = var.vpn_gateway_peer_export_path
}
