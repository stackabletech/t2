terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      version = "1.31.1"
    }
  }
}

variable "hcloud_token" {
  description = "Token to be used with Hetzner cloud"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the cluster, used as a prefix on the names of the resources created here"
  type        = string
}

provider "hcloud" {
  token = var.hcloud_token
}

module "stackable_package_versions_centos_8" {
  source = "./terraform_modules/stackable_package_versions_centos_8"
}

module "hcloud" {
  source                     = "./terraform_modules/hcloud"
  cluster_name               = var.cluster_name
  os_image                   = "centos-8"
}