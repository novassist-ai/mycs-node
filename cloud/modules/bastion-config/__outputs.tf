#
# Module Outputs
#

#
# Root CA for signing self-signed cert
#
output "root_ca_key" {
  value = local.root_ca_key
}

output "root_ca_cert" {
  value = local.root_ca_cert
}

# Cloud-Init configuration file setting 
# up the Bastion instance on first boot
output "bastion_cloud_init_config" {
  value = data.cloudinit_config.bastion-cloudinit.rendered
}

# Raw cloud-init config
output "bastion_cloud_init_config_raw" {
  value = element(data.cloudinit_config.bastion-cloudinit.part, 1).content
}

# The password generated for the VPN admin user
output "bastion_admin_password" {
  value = random_string.bastion-admin-password.result
}

output "bastion_admin_sshkey" {
  value     = tls_private_key.bastion-ssh-key.private_key_pem
  sensitive = true
}

output "bastion_openssh_public_key" {
  value = tls_private_key.bastion-ssh-key.public_key_openssh
}

# The api-key required to adminster the 
# internal zone managed by powerdns
output "powerdns_api_key" {
  value = random_string.powerdns-api-key.result
}
