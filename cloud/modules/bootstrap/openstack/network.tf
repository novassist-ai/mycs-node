#
# VPC networks, subnets and router
#

locals {
  dmz_cidr_block = (
    length(var.dmz_cidr) != 0
    ? var.dmz_cidr[0]
    : cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start)
  )
  admin_cidr_block = (
    length(var.admin_cidr) != 0
    ? var.admin_cidr[0]
    : (
      length(var.dmz_cidr) != 0
      ? cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start)
      : cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start + 1)
    )
  )
  admin_vlan_network = var.configure_admin_network && var.admin_vlan_id >= 0
  admin_network_id = (
    var.configure_admin_network
    ? openstack_networking_network_v2.admin[0].id
    : openstack_networking_network_v2.dmz.id
  )

  # Reserve the first and last 5 host addresses on the admin subnet for static
  # assignments (e.g. jumpbox at offset 5, bastion NAT at offset -3).
  # Neutron DHCP serves the range between them when bastion_as_nat is enabled.
  admin_dhcp_pool_start = cidrhost(local.admin_cidr_block, 6)
  admin_dhcp_pool_end   = cidrhost(local.admin_cidr_block, -6)
  admin_dhcp_pools = var.bastion_as_nat ? [
    {
      start = local.admin_dhcp_pool_start
      end   = local.admin_dhcp_pool_end
    },
  ] : []
}

moved {
  from = openstack_networking_network_v2.main
  to   = openstack_networking_network_v2.dmz
}

resource "openstack_networking_network_v2" "dmz" {
  name           = "${var.vpc_name}: dmz network"
  admin_state_up = true
}

resource "openstack_networking_network_v2" "admin" {
  count = var.configure_admin_network ? 1 : 0

  name           = "${var.vpc_name}: admin network"
  admin_state_up = true

  value_specs = local.admin_vlan_network ? {
    "provider:network_type"    = "vrack"
    "provider:segmentation_id" = var.admin_vlan_id
  } : {}
}

resource "openstack_networking_subnet_v2" "dmz" {
  name            = "${var.vpc_name}: dmz subnet"
  network_id      = openstack_networking_network_v2.dmz.id
  cidr            = local.dmz_cidr_block
  ip_version      = 4
  dns_nameservers = []
}

resource "openstack_networking_subnet_v2" "admin" {
  count = var.configure_admin_network ? 1 : 0

  name            = "${var.vpc_name}: admin subnet"
  network_id      = openstack_networking_network_v2.admin[0].id
  cidr            = local.admin_cidr_block
  ip_version      = 4
  dns_nameservers = []
  gateway_ip      = var.bastion_as_nat ? local.bastion_admin_itf_ip : null

  dynamic "allocation_pool" {
    for_each = local.admin_dhcp_pools
    content {
      start = allocation_pool.value.start
      end   = allocation_pool.value.end
    }
  }
}

resource "openstack_networking_router_v2" "main" {
  name                = "${var.vpc_name}: router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "dmz" {
  router_id = openstack_networking_router_v2.main.id
  subnet_id = openstack_networking_subnet_v2.dmz.id
}
