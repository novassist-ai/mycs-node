#
# Module Outputs
#

#
# Root CA for signing self-signed cert
#
output "root_ca_key" {
  value = module.config.root_ca_key
}

output "root_ca_cert" {
  value = module.config.root_ca_cert
}

#
# VPC and network resource attributes
#

output "vpc_id" {
  value = var.vpc_name
}

output "vpc_name" {
  value = var.vpc_name
}

output "dmz_network" {
  value = google_compute_network.dmz.self_link
}

output "dmz_subnetworks" {
  value = [google_compute_subnetwork.dmz.self_link]
}

output "admin_network" {
  value = local.admin_network_self_link
}

output "admin_subnetworks" {
  value = [local.admin_network_self_link]
}

output "lan_subnet_cidrs" {
  description = "CIDR blocks for bastion LAN subnets (DMZ public-side and admin internal)."
  value = {
    vpc   = var.vpc_cidr
    dmz   = [google_compute_subnetwork.dmz.ip_cidr_range]
    admin = var.configure_admin_network ? [google_compute_subnetwork.admin[0].ip_cidr_range] : [google_compute_subnetwork.dmz.ip_cidr_range]
  }
}

output "admin_security_group" {
  value = ""
}

output "vpc_dns_public_zone_id" {
  value = var.attach_dns_zone ? google_dns_managed_zone.vpc.0.name : ""
}

output "vpc_dns_public_zone_name" {
  value = var.attach_dns_zone ? google_dns_managed_zone.vpc.0.dns_name : ""
}

#
# Bastion resource attributes
#

output "bastion_instance_id" {
  value = google_compute_instance.bastion.instance_id
}

output "bastion_public_ip" {
  value = google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip
}

output "bastion_admin_ip" {
  value = local.bastion_admin_itf_ip
}

output "bastion_fqdn" {
  value = (var.attach_dns_zone
    ? google_dns_record_set.vpc-public.0.name
    : var.bastion_use_fqdn
      ? "${replace(google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip, ".", "-")}.mycs.appbricks.org"
      : ""
  )
}

output "bastion_admin_fqdn" {
  value = (
    length(var.bastion_host_name) > 0 && !var.bastion_allow_public_ssh 
      ? google_dns_record_set.vpc-admin.0.name 
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
  value = module.config.bastion_admin_password
}

output "bastion_admin_sshkey" {
  value     = module.config.bastion_admin_sshkey
  sensitive = true
}

output "bastion_openssh_public_key" {
  value = module.config.bastion_openssh_public_key
}

#
# The url and api-key required to adminster
# the internal zone managed by powerdns
#

output "powerdns_url" {
  value = "http://${local.bastion_admin_itf_ip}:8888"
}

output "powerdns_api_key" {
  value     = module.config.powerdns_api_key
  sensitive = true
}

#
# Default SSH key to use within VPC
#

output "default_openssh_private_key" {
  value = tls_private_key.default-ssh-key.private_key_pem
}

output "default_openssh_public_key" {
  value = tls_private_key.default-ssh-key.public_key_openssh
}

output "default_ssh_key_pair" {
  value = ""
}

# ==== DEBUG OUTPUT ====

# output "debug_output" {
#   value = module.config.debug_output
# }