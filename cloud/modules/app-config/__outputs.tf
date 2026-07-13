#
# Module Outputs
#

output "app_config_files" {
  value = {
    "/etc/mycs/mycs-key-${var.mycs_cloud_public_key_id}.pem" = var.mycs_cloud_public_key
    "/etc/mycs/node-private-key.pem" = var.mycs_app_private_key
    "/etc/mycs/local-ca-root.pem" = var.mycs_space_ca_root
    "/etc/mycs/config.yml" = local.mycs_app_config
    "/etc/mycs/version" = var.mycs_app_version
  }
}

# Cloud-Init configuration file for setting 
# up a applications instance on first boot
output "app_cloud_init_config" {
  value = data.cloudinit_config.app-cloudinit.rendered
}
