terraform {
  required_version = "~> 0.15"
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

variable "ionos_datacenter" {
  description = "Name of the datacenter in the IONOS cloud - set using environment variable TF_VAR_ionos_datacenter"
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
  datacenter_name               = var.ionos_datacenter
  os_name                       = "CentOS"
  os_version                    = "8"
  cluster_public_key_filename   = "${path.module}/cluster_key.pub"
  cluster_private_key_filename  = "${path.module}/cluster_key"
}


