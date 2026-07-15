#
# Module Outputs
#

#
# Root CA for signing self-signed cert
#
output "root_ca_key" {
  value     = module.config.root_ca_key
  sensitive = true
}

output "root_ca_cert" {
  value = module.config.root_ca_cert
}

#
# Network resource attributes
#

output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_name" {
  value = var.vpc_name
}

output "dmz_subnetworks" {
  value = aws_subnet.dmz.*.id
}

output "admin_subnetworks" {
  value = (var.configure_admin_network 
    ? aws_subnet.admin.*.id
    : aws_subnet.dmz.*.id
  )
}

output "lan_subnet_cidrs" {
  description = "CIDR blocks for bastion LAN subnets (DMZ public-side and admin internal)."
  value = {
    vpc   = var.vpc_cidr
    dmz   = aws_subnet.dmz[*].cidr_block
    admin = var.configure_admin_network ? aws_subnet.admin[*].cidr_block : aws_subnet.dmz[*].cidr_block
  }
}

output "admin_security_group" {
  value = aws_security_group.internal.id
}

output "vpc_dns_public_zone_id" {
  value = var.attach_dns_zone ? aws_route53_zone.vpc-public.0.zone_id : ""
}

output "vpc_dns_public_zone_name" {
  value = var.attach_dns_zone ? aws_route53_zone.vpc-public.0.name : ""
}

output "vpc_dns_private_zone_id" {
  value = var.attach_dns_zone ? aws_route53_zone.vpc-private.0.zone_id : ""
}

output "vpc_dns_private_zone_name" {
  value = var.attach_dns_zone ? aws_route53_zone.vpc-private.0.name : ""
}

#
# Bastion resource attributes
#

output "bastion_instance_id" {
  value = aws_instance.bastion.id
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "bastion_admin_ip" {
  value = local.bastion_admin_itf_ip
}

output "bastion_fqdn" {
  value = (
    var.attach_dns_zone 
      ? aws_route53_record.vpc-external.0.name 
      : aws_instance.bastion.public_dns
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
  value     = tls_private_key.default-ssh-key.private_key_pem
  sensitive = true
}

output "default_openssh_public_key" {
  value = tls_private_key.default-ssh-key.public_key_openssh
}

output "default_ssh_key_pair" {
  value = aws_key_pair.default.key_name
}

# ==== DEBUG OUTPUT ====

# output "debug_output" {
#   value = module.config.debug_output
# }