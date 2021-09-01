# Main file of the template pluscloud-open-centos-8
#
# 'Pluscloud open' is an SCS implementation building on OpenStack, which is why
# this template largely builds on the OpenStack Terraform provider
#
# Prerequisites:
#
# - a Pluscloud open account with enough headroom for the given cluster
# - a security group named 'default' allowing SSH access to the instances
# - all resources whose ids or names are required in the variables (and described just there)

terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "1.43.0"
    }
  }
}

variable "pluscloud_open_username" {
  description = "Username to be used with Pluscloud open - set using environment variable TF_VAR_pluscloud_open_username"
  type        = string
  sensitive   = true
}

variable "pluscloud_open_password" {
  description = "Password to be used with Pluscloud open - set using environment variable TF_VAR_pluscloud_open_password"
  type        = string
  sensitive   = true
}

variable "pluscloud_open_project_id" {
  description = "Project ID in Pluscloud open - set using environment variable TF_VAR_pluscloud_open_project_id"
  type        = string
  sensitive   = true
}

variable "pluscloud_open_domain_name" {
  description = "Domain to use in Pluscloud open - set using environment variable TF_VAR_pluscloud_open_domain_name"
  type        = string
  sensitive   = true
}

variable "pluscloud_open_auth_url" {
  description = "Authentication URL to use in Pluscloud open - set using environment variable TF_VAR_pluscloud_open_auth_url"
  type        = string
  sensitive   = true
}

variable "pluscloud_open_external_network_id" {
  description = "Authentication URL to use in Pluscloud open - set using environment variable TF_VAR_pluscloud_open_external_network_id"
  type        = string
  sensitive   = true
}

variable "pluscloud_open_ip_pool_name" {
  description = "Authentication URL to use in Pluscloud open - set using environment variable TF_VAR_pluscloud_open_ip_pool_name"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the cluster, used as a prefix on the names of the resources created here"
  type        = string
}

provider "openstack" {
  tenant_id         = var.pluscloud_open_project_id
  user_domain_name  = var.pluscloud_open_domain_name
  user_name         = var.pluscloud_open_username
  password          = var.pluscloud_open_password
  auth_url          = var.pluscloud_open_auth_url
  region            = yamldecode(file("cluster.yaml"))["spec"]["region"]
}

locals {
  stackable_user = "centos"
  stackable_user_home = "/home/centos/"
}

# Keypair (as files on disk where Terraform is executed)
module "master_keypair" {
  source      = "./terraform_modules/master_keypair"
  filename    = "${path.module}/cluster_key"
}

# Keypair (as Openstack resource)
resource "openstack_compute_keypair_v2" "master_keypair" {
  name       = "${var.cluster_name}-master-key"
  public_key = module.master_keypair.public_key_openssh
}

# Creates a file containing the desired (or default) versions of Stackable
# components in the Ansible inventory
module "stackable_package_versions_centos" {
  source      = "./terraform_modules/stackable_package_versions_centos"
}

module "stackable_service_definitions" {
  source = "./terraform_modules/stackable_service_definitions"
}

# Creates the subnet for this cluster
module "openstack_network" {
  source                        = "./terraform_modules/openstack_network"
  cluster_name                  = var.cluster_name
  external_network_id           = var.pluscloud_open_external_network_id
  ip_pool                       = var.pluscloud_open_ip_pool_name
}

# Creates the bastion host for this cluster
module "openstack_nat" {
  source                        = "./terraform_modules/openstack_nat"
  cluster_name                  = var.cluster_name
  cluster_ip                    = module.openstack_network.cluster_ip
  network_name                  = module.openstack_network.network_name
  keypair_name                  = openstack_compute_keypair_v2.master_keypair.name
  cluster_private_key_filename  = "${path.module}/cluster_key"
  stackable_user                = local.stackable_user
  network_ready_flag            = module.openstack_network.network_ready_flag
}

# Creates the protected (=accessible via bastion host only) nodes of this cluster
module "openstack_protected_nodes" {
  source                        = "./terraform_modules/openstack_protected_nodes"
  cluster_name                  = var.cluster_name
  cluster_ip                    = module.openstack_network.cluster_ip
  network_name                  = module.openstack_network.network_name
  keypair_name                  = openstack_compute_keypair_v2.master_keypair.name
  cluster_private_key_filename  = "${path.module}/cluster_key"
  stackable_user                = local.stackable_user
  network_ready_flag            = module.openstack_network.network_ready_flag
}

# Creates the Ansible inventory file(s) for this cluster
module "openstack_inventory" {
  source                        = "./terraform_modules/openstack_inventory"
  orchestrator                  = module.openstack_protected_nodes.orchestrator
  nodes                         = module.openstack_protected_nodes.nodes
  cluster_private_key_filename  = "${path.module}/cluster_key"
  cluster_ip                    = module.openstack_network.cluster_ip
  bastion_host_internal_ip      = module.openstack_nat.bastion_host_internal_ip
  stackable_user                = local.stackable_user
  stackable_user_home           = local.stackable_user_home
}

# Creates the Stackable client script to access the cluster once it's up and running
module "stackable_client_script" {
  source                        = "./terraform_modules/stackable_client_script"
  nodes                         = [for node in module.openstack_protected_nodes.nodes : 
    { name = node.metadata["hostname"], ip = node.access_ip_v4 }
  ]
  orchestrator_ip               = module.openstack_protected_nodes.orchestrator.access_ip_v4
  cluster_ip                    = module.openstack_network.cluster_ip
  ssh-username                  = local.stackable_user
}
