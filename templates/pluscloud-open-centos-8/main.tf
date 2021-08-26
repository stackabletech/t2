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

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

provider "openstack" {
  tenant_id         = "fdcd63edfbb54829a657e2be9a71849a"
  user_domain_name  = "stackable.de"
  user_name         = var.pluscloud_open_username
  password          = var.pluscloud_open_password
  auth_url          = "https://api.gx-scs.sovereignit.cloud:5000"
  region            = "RegionOne"
}

module "master_keypair" {
  source      = "./terraform_modules/master_keypair"
  filename    = "${path.module}/cluster_key"
}

resource "openstack_compute_keypair_v2" "master_keypair" {
  name       = "${var.cluster_name}-master-key"
  public_key = module.master_keypair.public_key_openssh
}

module "stackable_package_versions_centos" {
  source      = "./terraform_modules/stackable_package_versions_centos"
}

module "openstack_network" {
  source                        = "./terraform_modules/openstack_network"
  cluster_name                  = var.cluster_name
  external_network_id           = "a882b33a-f52e-4e0e-872d-140606e16930"
  ip_pool                       = "ext01"
}

module "openstack_nat" {
  source                        = "./terraform_modules/openstack_nat"
  cluster_name                  = var.cluster_name
  cluster_ip                    = module.openstack_network.cluster_ip
  network_name                  = module.openstack_network.network_name
  keypair_name                  = openstack_compute_keypair_v2.master_keypair.name
  network_ready_flag            = module.openstack_network.network_ready_flag
}

module "openstack_protected_nodes" {
  source                        = "./terraform_modules/openstack_protected_nodes"
  cluster_name                  = var.cluster_name
  network_name                  = module.openstack_network.network_name
  keypair_name                  = openstack_compute_keypair_v2.master_keypair.name
  network_ready_flag            = module.openstack_network.network_ready_flag
}

module "openstack_inventory" {
  source                        = "./terraform_modules/openstack_inventory"
  orchestrator                  = module.openstack_protected_nodes.orchestrator
  nodes                         = module.openstack_protected_nodes.nodes
  cluster_private_key_filename  = "${path.module}/cluster_key"
  cluster_ip                    = module.openstack_network.cluster_ip
  stackable_user                = "centos"
}


