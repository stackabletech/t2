terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      version = "1.42.1"
    }
  }
}

variable "hcloud_token" {
  description = "Token to be used with Hetzner cloud"
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

provider "hcloud" {
  token = var.hcloud_token
}

module "stackable_component_versions" {
  source = "./terraform_modules/stackable_component_versions"
}

module "hcloud" {
  source                     = "./terraform_modules/hcloud"
  cluster_id                 = var.cluster_id
  cluster_name               = local.cluster_name
  os_image                   = "centos-stream-8"
  metadata_cloud_vendor      = "Hetzner Cloud"
  metadata_k8s               = "K3s"
  metadata_node_os           = "CentOS 8"
}