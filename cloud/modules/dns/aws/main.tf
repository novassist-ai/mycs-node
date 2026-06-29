#
# AWS Route53 (public DNS only)
#

data "aws_route53_zone" "parent" {
  name = local.aws_parent_zone_name
}

resource "aws_route53_zone" "public" {
  name = var.vpc_dns_zone

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_route53_record" "public_ns" {
  zone_id = data.aws_route53_zone.parent.zone_id
  name    = var.vpc_dns_zone
  type    = "NS"
  ttl     = "30"

  records = [
    aws_route53_zone.public.name_servers[0],
    aws_route53_zone.public.name_servers[1],
    aws_route53_zone.public.name_servers[2],
    aws_route53_zone.public.name_servers[3],
  ]
}

resource "aws_route53_record" "bastion_public" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "${var.vpc_dns_zone}."

  type = "A"
  ttl  = "300"

  records = [var.bastion_public_ip]
}

resource "aws_route53_record" "bastion_admin" {
  count = (
    length(var.bastion_host_name) > 0
    && !var.bastion_allow_public_ssh
  ) ? 1 : 0

  zone_id = aws_route53_zone.public.zone_id
  name    = "${var.bastion_host_name}.${var.vpc_dns_zone}."

  type = "A"
  ttl  = "300"

  records = [var.bastion_admin_itf_ip]
}

resource "aws_route53_record" "mail" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  zone_id = aws_route53_zone.public.zone_id
  name    = "mail.${var.vpc_dns_zone}."
  type    = "A"
  ttl     = "300"
  records = [var.bastion_admin_itf_ip]
}

resource "aws_route53_record" "mx" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  zone_id = aws_route53_zone.public.zone_id
  name    = "${var.vpc_dns_zone}."
  type    = "MX"
  ttl     = "300"
  records = ["1 ${aws_route53_zone.public.zone_id}"]
}

resource "aws_route53_record" "txt" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  zone_id = aws_route53_zone.public.zone_id
  name    = "${var.vpc_dns_zone}."
  type    = "TXT"
  ttl     = "300"
  records = ["v=spf1 mx -all"]
}
