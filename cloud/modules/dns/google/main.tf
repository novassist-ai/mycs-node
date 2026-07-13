#
# Google Cloud DNS (public DNS only)
#

data "google_dns_managed_zone" "parent" {
  name = local.google_parent_managed_zone_name
}

resource "google_dns_managed_zone" "vpc" {
  name     = replace(var.vpc_dns_zone, ".", "-")
  dns_name = "${var.vpc_dns_zone}."
}

resource "google_dns_record_set" "vpc_ns" {
  name         = "${var.vpc_dns_zone}."
  managed_zone = data.google_dns_managed_zone.parent.name

  type = "NS"
  ttl  = 300

  rrdatas = [
    google_dns_managed_zone.vpc.name_servers[0],
    google_dns_managed_zone.vpc.name_servers[1],
    google_dns_managed_zone.vpc.name_servers[2],
    google_dns_managed_zone.vpc.name_servers[3],
  ]
}

resource "google_dns_record_set" "vpc_public" {
  name         = "${var.vpc_dns_zone}."
  managed_zone = google_dns_managed_zone.vpc.name

  type    = "A"
  ttl     = "300"
  rrdatas = [var.bastion_public_ip]
}

resource "google_dns_record_set" "vpc_admin" {
  count = (
    length(var.bastion_host_name) > 0
    && !var.bastion_allow_public_ssh
  ) ? 1 : 0

  name         = "${var.bastion_host_name}.${var.vpc_dns_zone}."
  managed_zone = google_dns_managed_zone.vpc.name

  type    = "A"
  ttl     = "300"
  rrdatas = [var.bastion_admin_itf_ip]
}

resource "google_dns_record_set" "vpc_mail" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  name         = "mail.${var.vpc_dns_zone}."
  managed_zone = google_dns_managed_zone.vpc.name

  type    = "A"
  ttl     = "300"
  rrdatas = [var.bastion_admin_itf_ip]
}

resource "google_dns_record_set" "vpc_mx" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  name         = "${var.vpc_dns_zone}."
  managed_zone = google_dns_managed_zone.vpc.name

  type    = "MX"
  ttl     = "300"
  rrdatas = ["1 ${google_dns_record_set.vpc_public.name}"]
}

resource "google_dns_record_set" "vpc_txt" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  name         = "${var.vpc_dns_zone}."
  managed_zone = google_dns_managed_zone.vpc.name

  type    = "TXT"
  ttl     = "300"
  rrdatas = ["\"v=spf1 mx -all\""]
}
