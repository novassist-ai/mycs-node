#
# Module Outputs
#

output "root_ca_key" {
  value     = module.config.root_ca_key
  sensitive = true
}

output "root_ca_cert" {
  value = module.config.root_ca_cert
}

output "vpc_id" {
  value = openstack_networking_network_v2.dmz.id
}

output "vpc_name" {
  value = var.vpc_name
}

output "dmz_subnetworks" {
  value = [openstack_networking_subnet_v2.dmz.id]
}

output "admin_subnetworks" {
  value = (
    var.configure_admin_network
    ? [openstack_networking_subnet_v2.admin[0].id]
    : [openstack_networking_subnet_v2.dmz.id]
  )
}

output "lan_subnet_cidrs" {
  description = "CIDR blocks for bastion LAN subnets (DMZ public-side and admin internal)."
  value = {
    vpc   = var.vpc_cidr
    dmz   = [local.dmz_cidr_block]
    admin = var.configure_admin_network ? [local.admin_cidr_block] : [local.dmz_cidr_block]
  }
}

output "admin_security_group" {
  value = openstack_networking_secgroup_v2.internal.id
}

output "vpc_dns_public_zone_id" {
  value = local.dns_vpc_dns_public_zone_id
}

output "vpc_dns_public_zone_name" {
  value = local.dns_vpc_dns_public_zone_name
}

output "vpc_dns_private_zone_id" {
  value = ""
}

output "vpc_dns_private_zone_name" {
  value = ""
}

output "bastion_instance_id" {
  value = openstack_compute_instance_v2.bastion.id
}

output "bastion_public_ip" {
  value = openstack_networking_floatingip_v2.bastion_public.address
}

output "bastion_admin_ip" {
  value = local.bastion_admin_itf_ip
}

output "bastion_fqdn" {
  value = (
    var.attach_dns_zone
    ? var.vpc_dns_zone
    : openstack_networking_floatingip_v2.bastion_public.address
  )
}

output "bastion_admin_fqdn" {
  value = (
    length(var.bastion_host_name) > 0 && !var.bastion_allow_public_ssh
    ? join(".", tolist([var.bastion_host_name, var.vpc_dns_zone]))
    : "N/A"
  )
}

output "bastion_admin_api_port" {
  value = var.bastion_admin_api_port
}

output "bastion_admin_ssh_port" {
  value = var.bastion_admin_ssh_port
}

output "bastion_admin_user" {
  value = var.bastion_admin_user
}

output "bastion_admin_password" {
  value     = module.config.bastion_admin_password
  sensitive = true
}

output "bastion_admin_sshkey" {
  value     = module.config.bastion_admin_sshkey
  sensitive = true
}

output "bastion_openssh_public_key" {
  value = module.config.bastion_openssh_public_key
}

output "powerdns_url" {
  value = "http://${local.bastion_admin_itf_ip}:8888"
}

output "powerdns_api_key" {
  value     = module.config.powerdns_api_key
  sensitive = true
}

output "default_openssh_private_key" {
  value     = tls_private_key.default-ssh-key.private_key_pem
  sensitive = true
}

output "default_openssh_public_key" {
  value = tls_private_key.default-ssh-key.public_key_openssh
}

output "default_ssh_key_pair" {
  value = openstack_compute_keypair_v2.default.name
}
