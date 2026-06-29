#
# Hosted zone for VPC
#

data "google_dns_managed_zone" "parent" {
  count = var.attach_dns_zone ? 1 : 0
  name  = var.dns_managed_zone_name
}

#
# Public Zone
#
resource "google_dns_managed_zone" "vpc" {
  count = var.attach_dns_zone ? 1 : 0
  
  name     = replace(var.vpc_dns_zone, ".", "-")
  dns_name = "${var.vpc_dns_zone}."
}

resource "google_dns_record_set" "vpc" {
  count = var.attach_dns_zone ? 1 : 0

  name         = "${var.vpc_dns_zone}."
  managed_zone = data.google_dns_managed_zone.parent.0.name

  type = "NS"
  ttl  = 300

  rrdatas = [
    google_dns_managed_zone.vpc.0.name_servers.0,
    google_dns_managed_zone.vpc.0.name_servers.1,
    google_dns_managed_zone.vpc.0.name_servers.2,
    google_dns_managed_zone.vpc.0.name_servers.3,
  ]
}

#
# VPC Bastion instance DNS
#

resource "google_dns_record_set" "vpc-public" {
  count = var.attach_dns_zone ? 1 : 0

  name         = "${var.vpc_dns_zone}."
  managed_zone = google_dns_managed_zone.vpc.0.name

  type    = "A"
  ttl     = "300"
  rrdatas = [google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip]
}

resource "google_dns_record_set" "vpc-admin" {
  count = var.attach_dns_zone && length(var.bastion_host_name) > 0 && !var.bastion_allow_public_ssh ? 1 : 0

  name = "${var.bastion_host_name}.${var.vpc_dns_zone}."

  managed_zone = google_dns_managed_zone.vpc.0.name

  type = "A"
  ttl  = "300"

  rrdatas = [local.bastion_admin_itf_ip]
}

resource "google_dns_record_set" "vpc-mail" {
  count = var.attach_dns_zone && length(var.smtp_relay_host) > 0 ? 1 : 0

  name         = "mail.${var.vpc_dns_zone}."
  managed_zone = google_dns_managed_zone.vpc.0.name

  type = "A"
  ttl  = "300"

  rrdatas = [local.bastion_admin_itf_ip]
}

resource "google_dns_record_set" "vpc-mx" {
  count = var.attach_dns_zone && length(var.smtp_relay_host) > 0 ? 1 : 0

  name         = "${var.vpc_dns_zone}."
  managed_zone = google_dns_managed_zone.vpc.0.name

  type    = "MX"
  ttl     = "300"
  rrdatas = ["1 ${google_dns_record_set.vpc-public.0.name}"]
}

resource "google_dns_record_set" "vpc-txt" {
  count = var.attach_dns_zone && length(var.smtp_relay_host) > 0 ? 1 : 0

  name         = "${var.vpc_dns_zone}."
  managed_zone = google_dns_managed_zone.vpc.0.name

  type    = "TXT"
  ttl     = "300"
  rrdatas = ["\"v=spf1 mx -all\""]
}
