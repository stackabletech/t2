terraform {
  required_version = ">= 0.15, < 2.0.0"
}

variable "aws_access_key" { 
  description = "AWS access key"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" { 
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

provider "aws" {
  region = yamldecode(file("cluster.yaml"))["spec"]["region"]
  access_key  = var.aws_access_key
  secret_key  = var.aws_secret_access_key
}

module "master_keypair" {
  source      = "./terraform_modules/master_keypair"
  filename    = "${path.module}/cluster_key"
}

resource "aws_key_pair" "master_keypair" {
  key_name = "${var.cluster_name}-master-key"
  public_key = module.master_keypair.public_key_openssh
}

module "aws_vpc" {
  source                = "./terraform_modules/aws_vpc"
  name                  = var.cluster_name
}

module "aws_nat" {
  source                        = "./terraform_modules/aws_nat"
  name_prefix                   = var.cluster_name
  vpc                           = module.aws_vpc.vpc
  key_pair                      = aws_key_pair.master_keypair
  cluster_private_key_filename  = "${path.module}/cluster_key"
}

module "aws_protected_nodes" {
  source                        = "./terraform_modules/aws_protected_nodes"
  name_prefix                   = var.cluster_name
  vpc                           = module.aws_vpc.vpc
  nat_gateway                   = module.aws_nat.nat_gateway
  key_pair                      = aws_key_pair.master_keypair
  cluster_private_key_filename  = "${path.module}/cluster_key"
  cluster_ip                    = module.aws_nat.cluster_ip
  dns_zone                      = module.aws_vpc.dns_zone
}

module "aws_ansible_inventory" {
  source                        = "./terraform_modules/aws_ansible_inventory"
  nodes                         = module.aws_protected_nodes.nodes
  orchestrator                  = module.aws_protected_nodes.orchestrator
  cluster_private_key_filename  = "${path.module}/cluster_key"
  cluster_ip                    = module.aws_nat.cluster_ip
}

module "stackable_package_versions_centos" {
  source = "./terraform_modules/stackable_package_versions_centos"
}

module "stackable_service_definitions" {
  source = "./terraform_modules/stackable_service_definitions"
}

module "wireguard" {
  count                     = can(yamldecode(file("cluster.yaml"))["spec"]["wireguard"]) ? (yamldecode(file("cluster.yaml"))["spec"]["wireguard"] ? 1 : 0) : 1 
  source                    = "./terraform_modules/wireguard"
  server_config_filename    = "ansible_roles/files/wireguard_server.conf"
  client_config_base_path   = "resources/wireguard-client-config"
  allowed_ips               = concat([ for node in module.aws_protected_nodes.nodes: node.private_ip ], [module.aws_protected_nodes.orchestrator.private_ip])
  endpoint_ip               = module.aws_nat.cluster_ip
}
