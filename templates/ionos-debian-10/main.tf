terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "6.3.1"
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

module "stackable_component_versions" {
  source = "./terraform_modules/stackable_component_versions"
}

module "ionos" {
  source                        = "./terraform_modules/ionos"
  datacenter_name               = var.cluster_name
  os_name                       = "Debian"
  os_version                    = "10-genericcloud-amd64-20220911-1135"
}
