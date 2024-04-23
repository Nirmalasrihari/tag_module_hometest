module "label_vpc" {
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  context    = module.base_label.context
  name       = "vpc"
  attributes = ["main"]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = module.label_vpc.tags
}

module "label_subnet_private" {
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  context    = module.base_label.context
  name       = "subnet-private"
  attributes = ["main"]
}

module "label_subnet_public" {
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  context    = module.base_label.context
  name       = "subnet-public"
  attributes = ["main"]
}

locals {
  vpc_cidr = var.vpc_cidr
}

# =========================
# Create your subnets here
# =========================
module "subnet_addrs" {
  source = "hashicorp/subnets/cidr"

  base_cidr_block = local.vpc_cidr
  networks = [
    {
      name     = "public"
      new_bits = 4
    },
    {
      name     = "private"
      new_bits = 4
    },
  ]
}

output "cidr-length-24-bit" {
 
  value = module.subnet_addrs.network_cidr_blocks["private"]
  
}

data "aws_availability_zones" "available" {
  state = "available"
} 

locals {
  private_cidr = module.subnet_addrs.network_cidr_blocks["private"]
  public_cidr = module.subnet_addrs.network_cidr_blocks["public"]
}


/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "ig" {
  vpc_id = "${aws_vpc.main.id}"
}
/* Elastic IP for NAT */
resource "aws_eip" "nat_eip" {
  domain   = "vpc"

  depends_on = [aws_internet_gateway.ig]
}
/* NAT */
resource "aws_nat_gateway" "nat" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id     = "${element(aws_subnet.public.*.id, 0)}"
  depends_on    = [aws_internet_gateway.ig]
 
}


resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidr
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = module.label_subnet_private.tags 
}


resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_cidr
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = module.label_subnet_public.tags 
}

/* Routing table for private subnet */
resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.main.id}"
  tags = module.label_subnet_private.tags 

}
/* Routing table for public subnet */
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.main.id}"
  tags = module.label_subnet_public.tags 
}
resource "aws_route" "public_internet_gateway" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.ig.id}"
  
}
resource "aws_route" "private_nat_gateway" {
  route_table_id         = "${aws_route_table.private.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.nat.id}"
  
}
/* Route table associations */
resource "aws_route_table_association" "public" {
  subnet_id      = "${aws_subnet.public.id}"
  route_table_id = "${aws_route_table.public.id}"
  
}
resource "aws_route_table_association" "private" {
  subnet_id      = "${aws_subnet.private.id}"
  route_table_id = "${aws_route_table.private.id}"
}

output "list_of_az" {
  value = data.aws_availability_zones.available.names[0]
}