#
# Inceptor bastion common config module
#

module "config" {
  source = "../../../modules/bastion-config"

  time_zone = var.time_zone

  mycs_node_private_key = var.mycs_node_private_key
  mycs_node_id_key      = var.mycs_node_id_key
  mycs_node_id          = var.mycs_node_id

  company_name      = var.company_name
  organization_name = var.organization_name
  locality          = var.locality
  province          = var.province
  country           = var.country

  root_ca_key  = var.root_ca_key
  root_ca_cert = var.root_ca_cert

  cert_domain_names = local.cert_domain_names

  vpc_name                 = var.vpc_name
  vpc_cidr                 = var.vpc_cidr
  vpc_dns_zone             = var.vpc_dns_zone
  vpc_internal_dns_zones   = var.vpc_internal_dns_zones
  vpc_internal_dns_records = concat(var.vpc_internal_dns_records, tolist([local.jumpbox_dns_record]))

  bastion_fqdn      = local.bastion_fqdn
  bastion_use_fqdn  = var.bastion_use_fqdn
  bastion_public_ip = local.bastion_public_ip

  certify_bastion = var.attach_dns_zone && var.certify_bastion

  bastion_dns = (
    length(var.bastion_dns) == 0
    ? cidrhost(var.vpc_cidr, 2)
    : var.bastion_dns
  )

  bastion_dmz_itf_ip   = local.bastion_dmz_itf_ip
  bastion_admin_itf_ip = local.bastion_admin_itf_ip

  bastion_nic_config = (
    var.configure_admin_network
    ? [
      join("|",
        tolist([
          local.bastion_dmz_itf_ip,
          openstack_networking_subnet_v2.dmz.cidr,
          "0.0.0.0/0",
          cidrhost(openstack_networking_subnet_v2.dmz.cidr, 1)
        ]),
      ),
      join("|",
        var.bastion_as_nat
        ? tolist([
          local.bastion_admin_itf_ip,
          openstack_networking_subnet_v2.admin[0].cidr,
          "",
          ""
        ])
        : tolist([
          local.bastion_admin_itf_ip,
          openstack_networking_subnet_v2.admin[0].cidr,
          length(var.global_internal_cidr) == 0 ? var.vpc_cidr : var.global_internal_cidr,
          cidrhost(openstack_networking_subnet_v2.admin[0].cidr, 1)
        ])
      )
    ]
    : [
      join("|",
        tolist([
          local.bastion_dmz_itf_ip,
          openstack_networking_subnet_v2.dmz.cidr,
          "0.0.0.0/0",
          cidrhost(openstack_networking_subnet_v2.dmz.cidr, 1)
        ]),
      )
    ]
  )

  data_volume_name = var.bastion_data_disk_device_name

  bastion_admin_api_port = var.bastion_admin_api_port
  bastion_admin_ssh_port = var.bastion_admin_ssh_port
  bastion_admin_user     = var.bastion_admin_user
  squidproxy_server_port = var.squidproxy_server_port

  vpn_type               = var.vpn_type
  vpn_network            = var.vpn_network
  vpn_restricted_network = local.vpn_restricted_network
  vpn_tunnel_all_traffic = var.vpn_tunnel_all_traffic
  vpn_idle_action        = var.vpn_idle_action
  vpn_idle_shutdown_time = var.vpn_idle_shutdown_time
  vpn_users              = join(",", var.vpn_users)

  ovpn_service_port = var.ovpn_service_port
  ovpn_protocol     = var.ovpn_protocol

  tunnel_vpn_port_start = var.tunnel_vpn_port_start
  tunnel_vpn_port_end   = var.tunnel_vpn_port_end

  wireguard_service_port = var.wireguard_service_port
  wireguard_subnet_ip    = local.wireguard_subnet_ip

  derp_stun_port = var.derp_stun_port

  smtp_relay_host    = var.smtp_relay_host
  smtp_relay_port    = var.smtp_relay_port
  smtp_relay_api_key = var.smtp_relay_api_key

  vpn_gateway_enabled  = var.vpn_gateway_enabled
  vpn_gateway_protocol = var.vpn_gateway_protocol
  vpn_gateway_nat      = var.vpn_gateway_nat

  vpn_gateway_peer_export_path = var.vpn_gateway_peer_export_path
  vpn_gateway_peer_config_paths = var.vpn_gateway_peer_config_paths
  bastion_admin_subnet_cidr = (
    var.configure_admin_network
    ? openstack_networking_subnet_v2.admin[0].cidr
    : openstack_networking_subnet_v2.dmz.cidr
  )
}

locals {
  vpn_restricted_network = (
    var.vpn_type == "wireguard"
    ? cidrsubnet(
      var.vpn_network,
      var.vpn_protected_sub_range,
      pow(2, var.vpn_protected_sub_range) - 1
    )
    : var.vpn_network
  )
  wireguard_subnet_ip = (
    var.vpn_type == "wireguard"
    ? "${cidrhost(var.vpn_network, 1)}/${split("/", var.vpn_network)[1]}"
    : "${cidrhost(var.wireguard_mesh_network, var.wireguard_mesh_node)}/${split("/", var.wireguard_mesh_network)[1]}"
  )
  bastion_public_ip = openstack_networking_floatingip_v2.bastion_public.address
  bastion_fqdn = (
    var.attach_dns_zone
    ? var.vpc_dns_zone
    : openstack_networking_floatingip_v2.bastion_public.address
  )
  cert_domain_names = (
    var.attach_dns_zone
    ? [
      "*.mycloudspace.io",
      var.vpc_dns_zone,
    ]
    : [
      "*.mycloudspace.io",
      "*.mycs.appbricks.org",
      openstack_networking_floatingip_v2.bastion_public.address,
      var.vpc_dns_zone,
    ]
  )
}
