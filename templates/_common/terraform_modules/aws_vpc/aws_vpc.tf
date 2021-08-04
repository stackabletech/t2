variable "name" { 
  description = "Name of the VPC in AWS"
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    "Name" = var.name
  }
}

resource "aws_route53_zone" "private" {
  name = yamldecode(file("cluster.yaml"))["domain"]
  vpc {
    vpc_id = aws_vpc.vpc.id
  }
  tags = {
    "Name" = "${var.name}-dns-zone"
  }
}

output "vpc" {
  value = aws_vpc.vpc
}

output "dns_zone" {
  value = aws_route53_zone.private
}