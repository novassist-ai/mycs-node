#
# Default SSH Key Pair
#

resource "tls_private_key" "default-ssh-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "openstack_compute_keypair_v2" "default" {
  name       = var.vpc_name
  public_key = tls_private_key.default-ssh-key.public_key_openssh
}

#
# External provider network
#

data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}
