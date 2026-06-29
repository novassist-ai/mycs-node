#
# Inception Bastion instance
#

data "openstack_compute_flavor_v2" "bastion" {
  name = var.bastion_flavor
}

data "openstack_images_image_v2" "bastion" {
  name_regex  = var.bastion_image_name_regex
  most_recent = true
}

locals {
  bastion_image_id = data.openstack_images_image_v2.bastion.id

  bastion_dmz_itf_ip = cidrhost(openstack_networking_subnet_v2.dmz.cidr, -3)
  bastion_admin_itf_ip = (
    var.configure_admin_network
    ? cidrhost(local.admin_cidr_block, -3)
    : local.bastion_dmz_itf_ip
  )
  bastion_dmz_security_groups = concat(
    [openstack_networking_secgroup_v2.bastion_public.id],
    var.configure_admin_network
    ? []
    : (
      var.bastion_as_nat
      ? [openstack_networking_secgroup_v2.internal.id]
      : [openstack_networking_secgroup_v2.bastion_private.id]
    )
  )
}

#
# Security groups
#

resource "openstack_networking_secgroup_v2" "internal" {
  name        = "${var.vpc_name}: internal"
  description = "Rules for ingress and egress of network traffic within VPC."
}

resource "openstack_networking_secgroup_rule_v2" "internal_ingress_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_group_id   = openstack_networking_secgroup_v2.internal.id
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_ingress_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_group_id   = openstack_networking_secgroup_v2.internal.id
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_ingress_icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_group_id   = openstack_networking_secgroup_v2.internal.id
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_ingress_bastion_tcp" {
  count = !var.bastion_as_nat ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = "${local.bastion_admin_itf_ip}/32"
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_ingress_bastion_udp" {
  count = !var.bastion_as_nat ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_ip_prefix  = "${local.bastion_admin_itf_ip}/32"
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_ingress_bastion_icmp" {
  count = !var.bastion_as_nat ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "${local.bastion_admin_itf_ip}/32"
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_ingress_vpn_peer_tcp" {
  for_each = var.bastion_as_nat ? toset(var.vpn_gateway_peer_cidrs) : toset([])

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_ingress_vpn_peer_udp" {
  for_each = var.bastion_as_nat ? toset(var.vpn_gateway_peer_cidrs) : toset([])

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_ingress_vpn_peer_icmp" {
  for_each = var.bastion_as_nat ? toset(var.vpn_gateway_peer_cidrs) : toset([])

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_egress_tcp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_egress_udp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_egress_icmp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.internal.id
}

resource "openstack_networking_secgroup_v2" "bastion_public" {
  name        = "${var.vpc_name}: bastion public"
  description = "Rules for ingress and egress of network traffic to bastion instance."
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_ssh" {
  count = var.bastion_allow_public_ssh ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(var.bastion_admin_ssh_port)
  port_range_max    = tonumber(var.bastion_admin_ssh_port)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_wireguard" {
  count = var.vpn_type == "wireguard" && length(var.wireguard_service_port) > 0 ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = tonumber(var.wireguard_service_port)
  port_range_max    = tonumber(var.wireguard_service_port)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_openvpn" {
  count = var.vpn_type == "openvpn" && length(var.ovpn_service_port) > 0 ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = var.ovpn_protocol
  port_range_min    = tonumber(var.ovpn_service_port)
  port_range_max    = tonumber(var.ovpn_service_port)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_ipsec_500" {
  count = var.vpn_type == "ipsec" ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 500
  port_range_max    = 500
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_ipsec_4500" {
  count = var.vpn_type == "ipsec" ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 4500
  port_range_max    = 4500
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_tunnel_udp" {
  count = length(var.tunnel_vpn_port_start) > 0 && length(var.tunnel_vpn_port_end) > 0 ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = tonumber(var.tunnel_vpn_port_start)
  port_range_max    = tonumber(var.tunnel_vpn_port_end)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_tunnel_tcp" {
  count = length(var.tunnel_vpn_port_start) > 0 && length(var.tunnel_vpn_port_end) > 0 ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(var.tunnel_vpn_port_start)
  port_range_max    = tonumber(var.tunnel_vpn_port_end)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_stun" {
  count = length(var.derp_stun_port) > 0 ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = tonumber(var.derp_stun_port)
  port_range_max    = tonumber(var.derp_stun_port)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_smtp" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 25
  port_range_max    = 25
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_icmp" {
  count = var.allow_bastion_icmp ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_egress_tcp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_egress_udp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_public_egress_icmp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_public.id
}

resource "openstack_networking_secgroup_v2" "bastion_private" {
  name        = "${var.vpc_name}: bastion private"
  description = "Rules for ingress and egress of network traffic to bastion admin interface."
}

resource "openstack_networking_secgroup_rule_v2" "bastion_private_squid" {
  count = length(var.squidproxy_server_port) > 0 ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(var.squidproxy_server_port)
  port_range_max    = tonumber(var.squidproxy_server_port)
  remote_ip_prefix  = var.vpn_network
  security_group_id = openstack_networking_secgroup_v2.bastion_private.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_private_squid_vpc" {
  count = length(var.squidproxy_server_port) > 0 ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(var.squidproxy_server_port)
  port_range_max    = tonumber(var.squidproxy_server_port)
  remote_ip_prefix  = var.vpc_cidr
  security_group_id = openstack_networking_secgroup_v2.bastion_private.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_private_egress_tcp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = var.vpc_cidr
  security_group_id = openstack_networking_secgroup_v2.bastion_private.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_private_egress_udp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_ip_prefix  = var.vpc_cidr
  security_group_id = openstack_networking_secgroup_v2.bastion_private.id
}

resource "openstack_networking_secgroup_rule_v2" "bastion_private_egress_icmp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = var.vpc_cidr
  security_group_id = openstack_networking_secgroup_v2.bastion_private.id
}

#
# Networking ports
#

resource "openstack_networking_port_v2" "bastion_dmz" {
  name               = "${var.vpc_name}: bastion-dmz"
  network_id         = openstack_networking_network_v2.dmz.id
  admin_state_up     = true
  security_group_ids = local.bastion_dmz_security_groups

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.dmz.id
    ip_address = local.bastion_dmz_itf_ip
  }
}

resource "openstack_networking_port_v2" "bastion_admin" {
  count = var.configure_admin_network ? 1 : 0

  name           = "${var.vpc_name}: bastion-admin"
  network_id     = local.admin_network_id
  admin_state_up = true
  security_group_ids = [
    var.bastion_as_nat
    ? openstack_networking_secgroup_v2.internal.id
    : openstack_networking_secgroup_v2.bastion_private.id
  ]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.admin[0].id
    ip_address = local.bastion_admin_itf_ip
  }

  allowed_address_pairs {
    ip_address = "0.0.0.0/0"
  }
}

resource "openstack_networking_floatingip_v2" "bastion_public" {
  pool = data.openstack_networking_network_v2.external.name
}

resource "openstack_networking_floatingip_associate_v2" "bastion_dmz" {
  floating_ip = openstack_networking_floatingip_v2.bastion_public.address
  port_id     = openstack_networking_port_v2.bastion_dmz.id

  depends_on = [
    openstack_networking_router_interface_v2.dmz,
  ]
}

#
# Bastion compute instance
#

resource "openstack_blockstorage_volume_v3" "bastion_data" {
  name = "${var.vpc_name}: bastion-data"
  size = var.bastion_data_disk_size
}

resource "openstack_compute_instance_v2" "bastion" {
  name            = "${var.vpc_name}: bastion"
  flavor_id       = data.openstack_compute_flavor_v2.bastion.id
  key_pair        = openstack_compute_keypair_v2.default.name

  block_device {
    uuid                  = local.bastion_image_id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = var.bastion_root_disk_size
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.bastion_dmz.id
  }

  dynamic "network" {
    for_each = var.configure_admin_network ? [1] : []
    content {
      port = openstack_networking_port_v2.bastion_admin[0].id
    }
  }

  user_data = module.config.bastion_cloud_init_config

  depends_on = [
    openstack_networking_router_interface_v2.dmz,
    openstack_networking_floatingip_associate_v2.bastion_dmz,
  ]
}

resource "openstack_compute_volume_attach_v2" "bastion_data" {
  instance_id = openstack_compute_instance_v2.bastion.id
  volume_id   = openstack_blockstorage_volume_v3.bastion_data.id
}
