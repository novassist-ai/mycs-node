#
# Availability Zones in current region
#

locals {
  num_azs = length(data.aws_availability_zones.available.names)
  num_azs_to_configure = min(var.max_azs, local.num_azs)
}

data "aws_availability_zones" "available" {}

#
# AWS Virtual Private Cloud
#

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

#
# Default Security Group allowing access from bastion 
# and to other instances with same security group.
#

resource "aws_security_group" "internal" {
  name        = "${var.vpc_name}: internal"
  description = "Rules for ingress and egress of network traffic within VPC."
  vpc_id      = aws_vpc.main.id

  # Allow all ingress traffic from instances 
  # having same security group
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "udp"
    self      = true
  }
  ingress {
    from_port = -1
    to_port   = -1
    protocol  = "icmp"
    self      = true
  }

  # If bastion is not acting as the NAT then it 
  # will not have the internal security group. So 
  # need to explicitly grant access to traffic 
  # from the bastion.
  dynamic "ingress" {
    for_each = !var.bastion_as_nat ? [1] : []
    content {
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      cidr_blocks = ["${local.bastion_admin_itf_ip}/32"]
    }
  }
  dynamic "ingress" {
    for_each = !var.bastion_as_nat ? [1] : []
    content {
      from_port   = 0
      to_port     = 65535
      protocol    = "udp"
      cidr_blocks = ["${local.bastion_admin_itf_ip}/32"]
    }
  }
  dynamic "ingress" {
    for_each = !var.bastion_as_nat ? [1] : []
    content {
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
      cidr_blocks = ["${local.bastion_admin_itf_ip}/32"]
    }
  }

  dynamic "ingress" {
    for_each = var.bastion_as_nat ? var.vpn_gateway_peer_cidrs : []
    content {
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }
  dynamic "ingress" {
    for_each = var.bastion_as_nat ? var.vpn_gateway_peer_cidrs : []
    content {
      from_port   = 0
      to_port     = 65535
      protocol    = "udp"
      cidr_blocks = [ingress.value]
    }
  }
  dynamic "ingress" {
    for_each = var.bastion_as_nat ? var.vpn_gateway_peer_cidrs : []
    content {
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.vpc_name}: internal"
  }
}

#
# Default SSH Key Pair
#

resource "tls_private_key" "default-ssh-key" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "aws_key_pair" "default" {
  key_name   = var.vpc_name
  public_key = tls_private_key.default-ssh-key.public_key_openssh
}
