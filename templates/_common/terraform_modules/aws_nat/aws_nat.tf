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

data "aws_availability_zones" "available" {}

# (public) subnet for the internet gateway, NAT and bastion host
resource "aws_subnet" "nat" {
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block = "10.0.2.0/24"
  vpc_id = var.vpc.id
  tags = {
    "Name" = "${var.name_prefix}-nat"
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
}
resource "aws_route_table_association" "internet_gateway_route_table" {
  subnet_id = aws_subnet.nat.id
  route_table_id = aws_route_table.internet_gateway_route_table.id
}

# public IP address for NAT gateway
resource "aws_eip" "nat_gateway" {
  vpc = true
}

# the NAT gateway to be used by the nodes in the private network
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id = aws_subnet.nat.id
  tags = {
    "Name" = "${var.name_prefix}-nat-gateway"
  }
}

output "nat_gateway" {
  value = aws_nat_gateway.nat_gateway
}

# security group for the bastion host
# (allowing only 22/SSH ingoing traffic)
resource "aws_security_group" "bastion_host" {
  name = "${var.name_prefix}-security-group-bastion-host"
  description = "Allows SSH access only to bastion host"
  vpc_id = var.vpc.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 22
    to_port = 22
    protocol = "tcp"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
  tags = {
    "Name" = "${var.name_prefix}-security-group-bastion-host"
  }
}

# bastion host
resource "aws_instance" "bastion_host" {
  instance_type = "t2.micro"
  ami = "ami-06ec8443c2a35b0ba" 
  subnet_id = aws_subnet.nat.id
  security_groups = [aws_security_group.bastion_host.id]
  key_name = var.key_pair.key_name
  disable_api_termination = false
  ebs_optimized = false
  root_block_device {
    volume_size = "25"
  }
  tags = {
    "Name" = "${var.name_prefix}-bastion-host"
  }
}

# public IP address for the bastion host
resource "aws_eip" "bastion_host" {
  instance = aws_instance.bastion_host.id
  vpc = true
}

# file containing IP address of bastion host.
resource "local_file" "ipv4_file" {
  filename = "ipv4"
  content = aws_eip.bastion_host.public_ip
  file_permission = "0440"
}

# script to ssh into bastion host
resource "local_file" "bastion-host-ssh-script" {
  filename = "ssh-bastion-host.sh"
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-bastion-host-script.tpl",
    {
      node_ip = aws_eip.bastion_host.public_ip
      ssh_key_private_path = var.cluster_private_key_filename
    }
  )
}



# cluster IP address
output "cluster_ip" {
  value = aws_eip.bastion_host.public_ip
}
