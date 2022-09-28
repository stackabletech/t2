terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      version = "1.35.2"
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

module "stackable_component_versions" {
  source = "./terraform_modules/stackable_component_versions"
}

module "hcloud" {
  source                     = "./terraform_modules/hcloud"
  cluster_name               = var.cluster_name
  os_image                   = "debian-11"
}