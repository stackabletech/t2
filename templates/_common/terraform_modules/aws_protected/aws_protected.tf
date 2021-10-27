variable "name_prefix" { 
  description = "Name prefix for all the resources created by this module"
}

variable "vpc" {
  description = "AWS VPC resource"
}

variable "nat_gateway" {
  description = "VPC NAT gateway to be used for outgoing traffic"
}

variable "key_pair" {
  description = "AWS Key Pair"
}

variable "node_configuration" {
}

variable "cluster_private_key_filename" {
  type = string
}

variable "dns_zone" {
  description = "DNS zone"
}

variable "dns_zone_reverse" {
  description = "DNS zone (reverse)"
}

variable "cluster_ip" {
  type = string
}

variable "stackable_user" {
  type = string
  description = "non-root user for Stackable"
}

# list of all node names to iterate over
locals {
  nodenames = [ for node in var.node_configuration: node.name ]
}

data "aws_availability_zones" "available" {}

# (private) subnet for the nodes of the cluster
resource "aws_subnet" "protected" {
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block = "10.0.1.0/24"
  vpc_id = var.vpc.id
  tags = {
    "Name" = "${var.name_prefix}-protected"
  }
}

# route table that sends all trafic towards the nat
resource "aws_route_table" "protected_nodes_route_table" {
  vpc_id = var.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = var.nat_gateway.id
  }
  tags = {
    "Name" = "${var.name_prefix}-nat-gateway-route-table"
  }
}

resource "aws_route_table_association" "protected_nodes_route_table" {
  subnet_id = aws_subnet.protected.id
  route_table_id = aws_route_table.protected_nodes_route_table.id
}

# security group for protected nodes
resource "aws_security_group" "protected_nodes" {
  name = "${var.name_prefix}-security-group-protected-nodes"
  description = "Allows all traffic"
  vpc_id = var.vpc.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
  tags = {
    "Name" = "${var.name_prefix}-security-group-protected-nodes"
  }
}

resource "aws_instance" "orchestrator" {
  instance_type = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["awsInstanceType"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["awsInstanceType"] : "t2.xlarge"
  ami = "ami-06ec8443c2a35b0ba"
  subnet_id = aws_subnet.protected.id
  security_groups = [aws_security_group.protected_nodes.id]
  key_name = var.key_pair.key_name
  disable_api_termination = false
  ebs_optimized = false
  root_block_device {
    volume_size = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskSizeGb"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskSizeGb"] : 50
    volume_type = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskType"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskType"] : "gp2"
    tags = {
      "Name" = "${var.name_prefix}-orchestrator-disk"
    }
  }
  tags = {
    "Name" = "${var.name_prefix}-orchestrator"
  }
}

resource "aws_route53_record" "orchestrator" {
  zone_id = var.dns_zone.zone_id
  name = "orchestrator"
  type = "A"
  ttl = "300"
  records = [aws_instance.orchestrator.private_ip]
}

resource "aws_route53_record" "orchestrator_reverse" {
  zone_id = var.dns_zone_reverse.zone_id
  name = element(split(".", aws_instance.orchestrator.private_ip), 3)
  type = "PTR"
  ttl = "300"
  records = [ format("%s.%s", "orchestrator", yamldecode(file("cluster.yaml"))["domain"]) ]
}

# script to ssh into orchestrator via ssh proxy (aka jump host)
module "ssh_script_orchestrator" {
  source                        = "../common_ssh_script_protected_node"
  cluster_ip                    = var.cluster_ip
  node_ip                       = aws_instance.orchestrator.private_ip
  user                          = var.stackable_user
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-orchestrator.sh"
}

resource "aws_instance" "node" {
  count = length(local.nodenames)
  instance_type = var.node_configuration[local.nodenames[count.index]].awsInstanceType
  ami = "ami-06ec8443c2a35b0ba"
  subnet_id = aws_subnet.protected.id
  security_groups = [aws_security_group.protected_nodes.id]
  key_name = var.key_pair.key_name
  disable_api_termination = false
  ebs_optimized = false
  root_block_device {
    volume_size = var.node_configuration[local.nodenames[count.index]].diskSizeGb
    volume_type = var.node_configuration[local.nodenames[count.index]].diskType
    tags = {
      "Name" = "${var.name_prefix}-${var.node_configuration[local.nodenames[count.index]].name}-disk"
    }
  }
  tags = {
    "Name" = "${var.name_prefix}-${var.node_configuration[local.nodenames[count.index]].name}"
    "hostname" = var.node_configuration[local.nodenames[count.index]].name
    "has_agent" = var.node_configuration[local.nodenames[count.index]].agent
  }
}

resource "aws_route53_record" "node" {
  count = length(local.nodenames)
  zone_id = var.dns_zone.zone_id
  name = var.node_configuration[local.nodenames[count.index]].name
  type = "A"
  ttl = "300"
  records = [element(aws_instance.node.*.private_ip, count.index)]
}

resource "aws_route53_record" "node_reverse" {
  count = length(local.nodenames)
  zone_id = var.dns_zone_reverse.zone_id
  name = element(split(".", element(aws_instance.node.*.private_ip, count.index)), 3)
  type = "PTR"
  ttl = "300"
  records = [ format("%s.%s", var.node_configuration[local.nodenames[count.index]].name, yamldecode(file("cluster.yaml"))["domain"]) ]
}

# script to ssh into nodes via ssh proxy (aka jump host)
module "ssh_script_nodes" {
  count                         = length(local.nodenames)
  source                        = "../common_ssh_script_protected_node"
  cluster_ip                    = var.cluster_ip
  node_ip                       = element(aws_instance.node.*.private_ip, count.index)
  user                          = var.stackable_user
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-${var.node_configuration[local.nodenames[count.index]].name}.sh"
}

output "nodes" {
  value = aws_instance.node
}

output "orchestrator" {
  value = aws_instance.orchestrator
}

