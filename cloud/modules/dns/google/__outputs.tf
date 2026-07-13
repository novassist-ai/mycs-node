output "vpc_dns_public_zone_id" {
  value = google_dns_managed_zone.vpc.id
}

output "vpc_dns_public_zone_name" {
  value = var.vpc_dns_zone
}

output "vpc_dns_private_zone_id" {
  value = ""
}

output "vpc_dns_private_zone_name" {
  value = ""
}

output "bastion_fqdn" {
  value = var.vpc_dns_zone
}
