#
# Outputs
#

output "region" {
  value = data.aws_region.default.region
}

output "vpc_id" {
  value = module.bootstrap.vpc_id
}

output "vpc_name" {
  value = module.bootstrap.vpc_name
}

output "lan_subnet_cidrs" {
  description = "CIDR blocks for bastion LAN subnets (DMZ and admin)."
  value       = module.bootstrap.lan_subnet_cidrs
}

output "bastion_instance_id" {
  value = module.bootstrap.bastion_instance_id
}

output "bastion_public_ip" {
  value = module.bootstrap.bastion_public_ip
}

output "bastion_fqdn" {
  value = module.bootstrap.bastion_fqdn
}

output "bastion_admin_fqdn" {
  value = module.bootstrap.bastion_admin_fqdn
}

output "bastion_admin_user" {
  value = module.bootstrap.bastion_admin_user
}

output "bastion_admin_password" {
  value = module.bootstrap.bastion_admin_password
}

output "concourse_admin_password" {
  value = "Passw0rd"
}

# ==== DEBUG OUTPUT ====

# output "debug_output" {
#   value = module.bootstrap.debug_output
# }