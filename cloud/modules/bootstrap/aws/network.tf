#
# VPC subnets
#

resource "aws_subnet" "dmz" {
  count = local.num_azs_to_configure

  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = !var.configure_admin_network

  # If DMZ CIDR is not provided then the a DMZ network will
  # be created for each AZ starting from ${var.vpc_subnet_start}
  cidr_block = (
    length(var.dmz_cidr) != 0 
      ? var.dmz_cidr[count.index] 
      : cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start+count.index)
  )

  tags = {
    Name = "${var.vpc_name}: dmz subnet ${count.index}"
  }
}

resource "aws_subnet" "admin" {
  count = var.configure_admin_network ? local.num_azs_to_configure : 0

  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # The AZ subnet CIDR should start on consective AZ counts so 
  # they are laid out in sequence. i.e. DMZ AZ1 CIDR 1, 
  # DMZ AZ2 CIDR 2, ADMIN AZ CIDR 4, ADMIN AZ CIDR 5 assuming 
  # the region has 3 AZs but only 2 are being configured.
  cidr_block = (
    length(var.admin_cidr) != 0 
      ? var.admin_cidr[count.index] 
      : (length(var.dmz_cidr) != 0 
        ? cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start + count.index) 
        : cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start+local.num_azs+count.index))
  )

  tags = {
    Name = "${var.vpc_name}: admin subnet ${count.index}"
  }
}

#
# VPC internet gateway
#

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}: internet gateway"
  }
}

resource "aws_route_table" "dmz" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.vpc_name}: dmz route table with igw"
  }
}

#
# VPC NAT gateway
#

resource "aws_eip" "nat" {
  count = var.bastion_as_nat ? 0 : local.num_azs_to_configure

  tags = {
    Name = "${var.vpc_name}: elastic ip for nat ${count.index}"
  }  
}

resource "aws_nat_gateway" "nat" {
  count = var.bastion_as_nat ? 0 : local.num_azs_to_configure

  allocation_id = element(aws_eip.nat.*.id, count.index)
  subnet_id     = element(aws_subnet.dmz.*.id, count.index)

  tags = {
    Name = "${var.vpc_name}: nat gateway ${count.index}"
  } 

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "admin" {
  count = var.configure_admin_network ? local.num_azs_to_configure : 0

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}: admin route table ${count.index} with nat"
  }
}

# Use Bastion as NAT
resource "aws_route" "nat-bastion" {
  count = var.configure_admin_network && var.bastion_as_nat ? local.num_azs_to_configure : 0
  
  route_table_id = aws_route_table.admin[count.index].id

  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.bastion-admin.0.id
}

# Use NAT instance
resource "aws_route" "nat-gateway" {
  count = var.configure_admin_network && !var.bastion_as_nat ? local.num_azs_to_configure : 0
  
  route_table_id = aws_route_table.admin[count.index].id

  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.nat.*.id, count.index)
}

#
# VPC Route tables
#

resource "aws_route_table_association" "dmz" {
  count = local.num_azs_to_configure

  subnet_id      = element(aws_subnet.dmz.*.id, count.index)
  route_table_id = aws_route_table.dmz.id
}

resource "aws_route_table_association" "admin" {
  count = var.configure_admin_network ? local.num_azs_to_configure : 0

  subnet_id      = element(aws_subnet.admin.*.id, count.index)
  route_table_id = element(aws_route_table.admin.*.id, count.index)
}
