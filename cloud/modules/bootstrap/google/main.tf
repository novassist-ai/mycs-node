#
# Availability Zones in current region
#

data "google_compute_zones" "available" {
  region = var.region
}

#
# Standard Ubuntu image
#

data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

#
# Default SSH Key Pair
#

resource "tls_private_key" "default-ssh-key" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

