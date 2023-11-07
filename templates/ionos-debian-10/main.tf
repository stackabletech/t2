terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "6.4.10"
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

variable "cluster_id" {
  description = "UUID of the cluster"
  type        = string
}

locals {
  cluster_name = "t2-${substr(var.cluster_id, 0, 8)}"
}

provider "ionoscloud" {
  username = var.ionos_username
  password = var.ionos_password
}

module "stackable_component_versions" {
  source = "./terraform_modules/stackable_component_versions"
}

module "ionos" {
  source                        = "./terraform_modules/ionos"
  cluster_id                    = var.cluster_id
  cluster_name                  = local.cluster_name
  datacenter_name               = local.cluster_name
  os_name                       = "Debian"
  os_version                    = "10-genericcloud-amd64-20220911-1135"
  metadata_cloud_vendor         = "IONOS Cloud"
  metadata_k8s                  = "K3s"
  metadata_node_os              = "Debian 10"
}
