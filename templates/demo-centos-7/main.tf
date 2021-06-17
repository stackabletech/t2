terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "5.0.4"
    }
  }
}

variable "ionos_username" {
  description = "Username to be used with the IONOS Cloud Provider - set using environment variable TF_VAR_ionos_username"
  type        = string
  sensitive   = true
}

variable "ionos_password" {
  description = "Password to be used with the IONOS Cloud Provider - set using environment variable TF_VAR_ionos_password"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

provider "ionoscloud" {
  username = var.ionos_username
  password = var.ionos_password
}

module "master_keypair" {
  source      = "./terraform_modules/master_keypair"
  filename    = "${path.module}/cluster_key"
}

module "stackable_package_versions_centos" {
  source      = "./terraform_modules/stackable_package_versions_centos"
}

module "ionos_protected_cluster" {
  source                        = "./terraform_modules/ionos_protected_cluster"
  datacenter_name               = var.cluster_name
  os_name                       = "CentOS"
  os_version                    = "7-server"
  cluster_public_key_filename   = "${path.module}/cluster_key.pub"
  cluster_private_key_filename  = "${path.module}/cluster_key"
}


