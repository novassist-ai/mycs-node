#
# Jumpbox
#

locals {
  local_dns = (
    length(var.vpc_internal_dns_zones) > 0 
      ? element(var.vpc_internal_dns_zones, 0) 
      : ""
  )
  jumpbox_dns = (
    var.deploy_jumpbox && length(local.local_dns) > 0 
      ? format("jumpbox.%s", local.local_dns) 
      : ""
  )
  jumpbox_dns_record = (
    length(local.jumpbox_dns) > 0 
      ? format("%s:%s", local.jumpbox_dns, aws_instance.jumpbox.0.private_ip) 
      : ""
  )
}

resource "aws_instance" "jumpbox" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  instance_type = var.jumpbox_instance_type
  ami           = data.aws_ami.ubuntu.id
  key_name      = aws_key_pair.default.key_name

  subnet_id = (
    var.configure_admin_network
      ? aws_subnet.admin.0.id
      : aws_subnet.dmz.0.id
  )
  availability_zone = data.aws_availability_zones.available.names[0]

  associate_public_ip_address = !var.configure_admin_network
  vpc_security_group_ids      = [aws_security_group.internal.id]

  root_block_device {
    volume_type = "standard"
  }

  tags = {
    Name = "${var.vpc_name}: jumpbox"
  }

  user_data = <<USERDATA
#cloud-config

write_files:
- encoding: b64
  content: ${base64encode(templatefile(
    "${path.module}/scripts/mount-volume.sh",
    {
      attached_device_name = var.jumpbox_data_disk_device_name
      mount_directory      = "/data"
      world_readable       = "true"
    }
  ))}
  path: /root/mount-volume.sh
  permissions: '0744'

runcmd: 

# Install Docker
- |
  rm -rf /var/lib/apt/lists/*
  echo "waiting 180 seconds for network to become available"
  timeout 180 /bin/bash -c \
    "until curl -s --fail $(cat /etc/apt/sources.list | head -1 | cut -d ' ' -f2) 2>&1 >/dev/null; do echo waiting ...; sleep 1; done"

  export DEBIAN_FRONTEND=noninteractive
  
  apt-get update
  apt-get -o Acquire::ForceIPv4=true install -y \
    pkg-config apt-transport-https ca-certificates gnupg lsb-release \
    cmake build-essential openssl libcurl4-openssl-dev libssl-dev libffi-dev libxml2 libxml2-dev \
    parted dosfstools squashfs-tools efibootmgr net-tools ipcalc \
    expect rsync curl jq zip git python3.9 python3-dev python3-pip python-is-python3
  
  distro=$(lsb_release -is | tr '[:upper:]' '[:lower:]')

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$distro/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/$distro \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  rm -fr awscliv2.zip aws

# Mount data volume
- /root/mount-volume.sh

USERDATA
}

#
# Jumpbox AMI
#

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.jumpbox_ami_name]
  }

  filter {
    name   = "architecture"
    values = [var.jumpbox_ami_arch]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.jumpbox_ami_owner]
}

#
# Persistant disk for data storage
#

resource "aws_ebs_volume" "jumpbox-data" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  size              = tonumber(var.jumpbox_data_disk_size)
  type              = "standard"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.vpc_name}: jumpbox data disk"
  }
}

resource "aws_volume_attachment" "jumpbox-data" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  volume_id    = aws_ebs_volume.jumpbox-data.0.id
  instance_id  = aws_instance.jumpbox.0.id
  force_detach = true

  # This name seems to be ignored by 
  # AWS but is required by the resource
  # so it is hard coded here
  device_name  = "/dev/xvdf"
}

#
# Jumpbox DNS
#

resource "aws_route53_record" "jumpbox" {
  count = var.attach_dns_zone && length(local.jumpbox_dns) > 0 ? 1 : 0

  zone_id = aws_route53_zone.vpc-private.0.zone_id
  name    = "jumpbox.${aws_route53_zone.vpc-private.0.name}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.jumpbox.0.private_ip]
}
