#
# Hosted zone for VPC
#

data "aws_route53_zone" "parent" {
  count = var.attach_dns_zone ? 1 : 0
  name  = "${replace(var.vpc_dns_zone, "/^[-0-9a-zA-Z]+\\./", "")}."
}

#
# Public Zone
#
resource "aws_route53_zone" "vpc-public" {
  count = var.attach_dns_zone ? 1 : 0
  
  name = var.vpc_dns_zone

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_route53_record" "vpc-public-ns" {
  count = var.attach_dns_zone ? 1 : 0

  zone_id = data.aws_route53_zone.parent.0.zone_id
  name    = var.vpc_dns_zone
  type    = "NS"
  ttl     = "30"

  records = [
    aws_route53_zone.vpc-public.0.name_servers.0,
    aws_route53_zone.vpc-public.0.name_servers.1,
    aws_route53_zone.vpc-public.0.name_servers.2,
    aws_route53_zone.vpc-public.0.name_servers.3,
  ]
}

#
# Private Zone
#
resource "aws_route53_zone" "vpc-private" {
  count = var.attach_dns_zone ? 1 : 0
  
  name = var.vpc_dns_zone

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name = var.vpc_name
  }
}

#
# VPC Bastion instance DNS
#

resource "aws_route53_record" "vpc-external" {
  count = var.attach_dns_zone ? 1 : 0

  zone_id = aws_route53_zone.vpc-public.0.zone_id
  name    = "${var.vpc_dns_zone}."
  
  type = "A"
  ttl  = "300"
  
  records = [aws_instance.bastion.public_ip]
}

resource "aws_route53_record" "vpc-internal" {
  count = var.attach_dns_zone ? 1 : 0

  zone_id = aws_route53_zone.vpc-private.0.zone_id
  name    = "${var.vpc_dns_zone}."

  type = "A"
  ttl  = "300"
  
  records = [local.bastion_dmz_itf_ip]
}

resource "aws_route53_record" "vpc-admin" {
  count = var.attach_dns_zone && length(var.bastion_host_name) > 0 && !var.bastion_allow_public_ssh ? 1 : 0

  zone_id = aws_route53_zone.vpc-private.0.zone_id
  name    = "${var.bastion_host_name}.${var.vpc_dns_zone}."

  type = "A"
  ttl  = "300"

  records = [local.bastion_admin_itf_ip]
}

resource "aws_route53_record" "vpc-mail" {
  count = var.attach_dns_zone && length(var.smtp_relay_host) > 0 ? 1 : 0

  zone_id = aws_route53_zone.vpc-public.0.zone_id
  name    = "mail.${var.vpc_dns_zone}."
  type    = "A"
  ttl     = "300"
  records = [local.bastion_admin_itf_ip]
}

resource "aws_route53_record" "vpc-mx" {
  count = var.attach_dns_zone && length(var.smtp_relay_host) > 0 ? 1 : 0

  zone_id = aws_route53_zone.vpc-public.0.zone_id
  name    = "${var.vpc_dns_zone}."
  type    = "MX"
  ttl     = "300"
  records = ["1 ${aws_route53_zone.vpc-public.0.zone_id}"]
}

resource "aws_route53_record" "vpc-txt" {
  count = var.attach_dns_zone && length(var.smtp_relay_host) > 0 ? 1 : 0

  zone_id = aws_route53_zone.vpc-public.0.zone_id
  name    = "${var.vpc_dns_zone}."
  type    = "TXT"
  ttl     = "300"
  records = ["v=spf1 mx -all"]
}
