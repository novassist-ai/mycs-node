#
# Virtual Networks
#

locals {
  admin_network_name = (var.configure_admin_network
    ? google_compute_network.admin.0.name
    : google_compute_network.dmz.name
  )
  admin_network_self_link = (var.configure_admin_network
    ? google_compute_network.admin.0.self_link
    : google_compute_network.dmz.self_link
  )
  admin_network_cidr_range = (var.configure_admin_network
    ? google_compute_subnetwork.admin.0.ip_cidr_range
    : google_compute_subnetwork.dmz.ip_cidr_range
  )
  admin_network_gateway_address = (var.configure_admin_network
    ? google_compute_subnetwork.admin.0.gateway_address
    : google_compute_subnetwork.dmz.gateway_address
  )
}

resource "google_compute_network" "dmz" {
  name                    = "${var.vpc_name}-dmz-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "dmz" {
  name = "${var.vpc_name}-dmz-subnet"

  ip_cidr_range = (
    length(var.dmz_cidr) != 0 
      ? var.dmz_cidr 
      : cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start)
  )

  network = google_compute_network.dmz.self_link
  region  = var.region
}

resource "google_compute_network" "admin" {
  count = var.configure_admin_network ? 1 : 0

  name                    = "${var.vpc_name}-admin-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "admin" {
  count = var.configure_admin_network ? 1 : 0

  name = "${var.vpc_name}-admin-subnet"

  ip_cidr_range = (
    length(var.admin_cidr) != 0 
      ? var.admin_cidr 
      : (length(var.dmz_cidr) != 0 
        ? cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start) 
        : cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start+1))
  )

  network = google_compute_network.admin.0.self_link
  region  = var.region
}
