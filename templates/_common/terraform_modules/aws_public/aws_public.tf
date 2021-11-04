variable "name_prefix" { 
  description = "Name prefix for all the resources created by this module"
}

variable "vpc" {
  description = "AWS VPC resource"
}

variable "key_pair" {
  description = "AWS Key Pair"
}

variable "cluster_private_key_filename" {
  type = string
}

variable "stackable_user" {
  type = string
  description = "non-root user for Stackable"
}

data "aws_availability_zones" "available" {}

# (public) subnet for the internet gateway, NAT and edge node
resource "aws_subnet" "public" {
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block = "10.0.2.0/24"
  vpc_id = var.vpc.id
  map_public_ip_on_launch = true
  tags = {
    "Name" = "${var.name_prefix}-public"
  }
}

# internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = var.vpc.id
  tags = {
    "Name" = "${var.name_prefix}-internet-gateway"
  }
}

# route table that sends all traffic towards the internet
resource "aws_route_table" "internet_gateway_route_table" {
  vpc_id = var.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
  tags = {
    "Name" = "${var.name_prefix}-internet-gateway-route-table"
  }
}

resource "aws_route_table_association" "internet_gateway_route_table" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.internet_gateway_route_table.id
}

# public IP address for NAT gateway
resource "aws_eip" "edge" {
  vpc = true
  tags = {
    "Name" = "${var.name_prefix}-public-ip"
  }
}

# the NAT gateway to be used by the nodes in the private network
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.edge.id
  subnet_id = aws_subnet.public.id
  tags = {
    "Name" = "${var.name_prefix}-nat-gateway"
  }
}

output "nat_gateway" {
  value = aws_nat_gateway.nat_gateway
}

# security group for the edge node
# (allowing only 22/SSH ingoing traffic)
resource "aws_security_group" "edge_node" {
  name = "${var.name_prefix}-security-group-edge-node"
  description = "Allows SSH access only to edge node"
  vpc_id = var.vpc.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 22
    to_port = 22
    protocol = "tcp"
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 52888
    protocol = "udp"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
  tags = {
    "Name" = "${var.name_prefix}-security-group-edge-node"
  }
}

# edge node
resource "aws_instance" "edge" {
  instance_type = "t2.micro"
  ami = "ami-06ec8443c2a35b0ba" 
  subnet_id = aws_subnet.public.id
  security_groups = [aws_security_group.edge_node.id]
  key_name = var.key_pair.key_name
  disable_api_termination = false
  ebs_optimized = false
  root_block_device {
    volume_size = "25"
    tags = {
      "Name" = "${var.name_prefix}-edge-disk"
    }
  }
  tags = {
    "Name" = "${var.name_prefix}-edge"
  }
}

# script to ssh into edge node
module "edge_node_host_ssh_script" {
  source                        = "../common_ssh_script_edge_node"
  ip                            = aws_instance.edge.public_ip
  user                          = var.stackable_user
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-edge.sh"
}

# cluster IP address
output "cluster_ip" {
  value = aws_instance.edge.public_ip
}
