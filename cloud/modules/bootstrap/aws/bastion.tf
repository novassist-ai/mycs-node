#
# Inception Bastion VM
#

resource "aws_instance" "bastion" {
  instance_type = var.bastion_instance_type
  ami           = data.aws_ami.bastion.id

  availability_zone = data.aws_availability_zones.available.names[0]

  root_block_device {
    volume_size = tonumber(var.bastion_root_disk_size)
    volume_type = var.bastion_root_disk_type
  }

  primary_network_interface {
    network_interface_id = aws_network_interface.bastion-dmz.id
  }

  tags = {
    Name = "${var.vpc_name}: bastion"
  }

  user_data_base64 = module.config.bastion_cloud_init_config
}

#
# Attached disk for saving persistant data. This disk needs to be
# large enough for any installation packages concourse downloads.
#

resource "aws_ebs_volume" "bastion-data" {
  size              = tonumber(var.bastion_data_disk_size)
  type              = var.bastion_data_disk_type
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_volume_attachment" "bastion-data" {
  volume_id    = aws_ebs_volume.bastion-data.id
  instance_id  = aws_instance.bastion.id
  force_detach = true

  # This name seems to be ignored by 
  # AWS but is required by the resource
  # so it is hard coded here
  device_name  = "/dev/xvdf"
}

#
# Attach additional network interface for admin network (when configured)
#

resource "aws_network_interface_attachment" "bastion-admin" {
  count = var.configure_admin_network ? 1 : 0

  instance_id          = aws_instance.bastion.id
  network_interface_id = aws_network_interface.bastion-admin.0.id
  device_index         = 1
}

#
# AMI
#

data "aws_ami" "bastion" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.bastion_image_name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.bastion_image_owner]
}

#
# Networking
#

locals {
  bastion_dmz_itf_ip   = cidrhost(aws_subnet.dmz.0.cidr_block, -3)
  bastion_admin_itf_ip = (
    var.configure_admin_network
      ? cidrhost(aws_subnet.admin.0.cidr_block, -3)
      : local.bastion_dmz_itf_ip
  )
}

resource "aws_network_interface" "bastion-dmz" {
  subnet_id       = aws_subnet.dmz.0.id
  private_ips     = [local.bastion_dmz_itf_ip]
  
  security_groups = concat(
    [aws_security_group.bastion-public.id],
    var.configure_admin_network
      ? []
      : var.bastion_as_nat 
        ? [aws_security_group.internal.id]
        : [aws_security_group.bastion-private.id]
  )

  tags = {
    Name = "${var.vpc_name}: bastion-dmz"
  }
}

resource "aws_network_interface" "bastion-admin" {
  count = var.configure_admin_network ? 1 : 0

  subnet_id   = aws_subnet.admin.0.id
  private_ips = [local.bastion_admin_itf_ip]

  security_groups = [
    var.bastion_as_nat 
      ? aws_security_group.internal.id 
      : aws_security_group.bastion-private.id
  ]

  # Enable traffic not destined 
  # for bastion to pass through
  source_dest_check = !var.bastion_as_nat

  tags = {
    Name = "${var.vpc_name}: bastion-admin"
  }
}

#
# Static external IP - created when admin network segment is configured
#

resource "aws_eip_association" "bastion" {
  count = var.configure_admin_network ? 1 : 0

  network_interface_id = aws_network_interface.bastion-dmz.id
  allocation_id        = aws_eip.bastion-public.0.id
}

resource "aws_eip" "bastion-public" {
  count = var.configure_admin_network ? 1 : 0

  tags = {
    Name = "${var.vpc_name}: bastion-public"
  }
}

#
# Security 
#

resource "aws_security_group" "bastion-public" {
  name        = "${var.vpc_name}: bastion public"
  description = "Rules for ingress and egress of network traffic to bastion instance."
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  dynamic "ingress" {
    for_each = var.bastion_allow_public_ssh ? [1] : []
    content {
      from_port   = tonumber(var.bastion_admin_ssh_port)
      to_port     = tonumber(var.bastion_admin_ssh_port)
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # VPN
  dynamic "ingress" {
    for_each = var.vpn_type == "wireguard" && length(var.wireguard_service_port) > 0 ? [1] : []
    content {
      from_port   = tonumber(var.wireguard_service_port)
      to_port     = tonumber(var.wireguard_service_port)
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  dynamic "ingress" {
    for_each = var.vpn_type == "openvpn" && length(var.ovpn_service_port) > 0 ? [1] : []
    content {
      from_port   = tonumber(var.ovpn_service_port)
      to_port     = tonumber(var.ovpn_service_port)
      protocol    = var.ovpn_protocol
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  dynamic "ingress" {
    for_each = var.vpn_type == "ipsec" ? [1] : []
    content {
      from_port   = 500
      to_port     = 500
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  dynamic "ingress" {
    for_each = var.vpn_type == "ipsec" ? [1] : []
    content {
      from_port   = 4500
      to_port     = 4500
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # VPN obfuscation tunnel
  dynamic "ingress" {
    for_each = length(var.tunnel_vpn_port_start) > 0 && length(var.tunnel_vpn_port_end) > 0 ? [1] : []
    content {
      from_port   = tonumber(var.tunnel_vpn_port_start)
      to_port     = tonumber(var.tunnel_vpn_port_end)
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  dynamic "ingress" {
    for_each = length(var.tunnel_vpn_port_start) > 0 && length(var.tunnel_vpn_port_end) > 0 ? [1] : []
    content {
      from_port   = tonumber(var.tunnel_vpn_port_start)
      to_port     = tonumber(var.tunnel_vpn_port_end)
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # STUN
  dynamic "ingress" {
    for_each = length(var.derp_stun_port) > 0 ? [1] : []
    content {
      from_port   = tonumber(var.derp_stun_port)
      to_port     = tonumber(var.derp_stun_port)
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # SMTP
  dynamic "ingress" {
    for_each = length(var.smtp_relay_host) > 0 ? [1] : []
    content {
      from_port   = 25
      to_port     = 25
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Allow ICMP
  dynamic "ingress" {
    for_each = var.allow_bastion_icmp ? [1] : []
    content {
      from_port   = "-1"
      to_port     = "-1"
      protocol    = "icmp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  #
  # Egress
  #

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
    Name = "${var.vpc_name}: bastion public security group"
  }
}

resource "aws_security_group" "bastion-private" {
  name        = "${var.vpc_name}: bastion private"
  description = "Rules for ingress and egress of network traffic to bastion instance."
  vpc_id      = aws_vpc.main.id

  # Squid Proxy
  dynamic "ingress" {
    for_each = length(var.squidproxy_server_port) > 0 ? [1] : []
    content {
      from_port   = tonumber(var.squidproxy_server_port)
      to_port     = tonumber(var.squidproxy_server_port)
      protocol    = "tcp"
      cidr_blocks = [var.vpn_network, var.vpc_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.vpc_name}: bastion private security group"
  }
}
