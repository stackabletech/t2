terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "6.4.3"
    }
  }
}

variable "cluster_id" {
  description = "ID of the cluster"
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "datacenter_name" {
  description = "Name of the datacenter"
  type        = string
}

variable "os_name" {
  description = "Name of the used OS, e.g. CentOS"
  type        = string
}

variable "os_version" {
  description = "Version of the used OS, e.g. 7-server-2022-03-01"
  type        = string
}

variable "metadata_cloud_vendor" {
  type = string
  description = "name of the cloud vendor this cluster runs on (for cluster metadata)"
}

variable "metadata_k8s" {
  type = string
  description = "Kubernetes flavor used in this cluster (for cluster metadata)"
}

variable "metadata_node_os" {
  type = string
  description = "operating system the Kubernetes nodes run on (for cluster metadata)"
}

# collect configuration information from cluster.yaml
locals {

  node_configuration = { for node in flatten([
    for type, definition in yamldecode(file("cluster.yaml"))["spec"]["nodes"] : [
      for i in range(1, definition.count + 1): {
        name = "${type}-${i}" 
        numberOfCores = can(definition.numberOfCores) ? definition.numberOfCores : 4
        memoryMb = can(definition.memoryMb) ? definition.memoryMb : 4096
        diskType = can(definition.diskType) ? definition.diskType : "SSD"
        diskSizeGb = can(definition.diskSizeGb) ? definition.diskSizeGb: 500
      }
    ]
  ]): node.name => node }

  datacenter_location = yamldecode(file("cluster.yaml"))["spec"]["region"]
  description = "t2-cluster-id: ${var.cluster_id}"
  domain = can(yamldecode(file("cluster.yaml"))["spec"]["domain"]) ? yamldecode(file("cluster.yaml"))["spec"]["domain"] : "stackable.test"
}

module "master_keypair" {
  source      = "../master_keypair"
  filename    = "cluster_key"
}

module "ionos_network" {
  source                        = "../ionos_network"
  datacenter_name               = var.datacenter_name
  datacenter_location           = local.datacenter_location
  datacenter_description        = local.description
}

module "ionos_edge_node" {
  source                        = "../ionos_edge_node"
  datacenter                    = module.ionos_network.datacenter
  external_lan                  = module.ionos_network.external_lan
  internal_lan                  = module.ionos_network.internal_lan
  cluster_public_key_filename   = "cluster_key.pub"
  cluster_private_key_filename  = "cluster_key"
}

module "ionos_protected_nodes" {
  source                        = "../ionos_protected_nodes"
  datacenter                    = module.ionos_network.datacenter
  internal_lan                  = module.ionos_network.internal_lan
  cluster_ip                    = module.ionos_edge_node.cluster_ip
  node_configuration            = local.node_configuration
  os_name                       = var.os_name
  os_version                    = var.os_version
  cluster_public_key_filename   = "cluster_key.pub"
  cluster_private_key_filename  = "cluster_key"
}

module "ionos_inventory" {
  source                        = "../ionos_inventory"
  cluster_id                    = var.cluster_id
  cluster_name                  = var.cluster_name
  cluster_ip                    = module.ionos_edge_node.cluster_ip
  edge_node_internal_ip         = module.ionos_edge_node.edge_node_internal_ip
  node_configuration            = local.node_configuration
  protected_nodes               = module.ionos_protected_nodes.protected_nodes
  orchestrator                  = module.ionos_protected_nodes.orchestrator
  nat_gateway_ip                = module.ionos_network.gateway_ip
  cluster_public_key_filename   = "cluster_key.pub"
  cluster_private_key_filename  = "cluster_key"
  location                      = local.datacenter_location
  domain                        = local.domain
}

module "stackable_service_definitions" {
  source = "../stackable_service_definitions"
}

# convert the metadata/annotations from the cluster definition to Ansible variables
# and add specific values for the template
module "metadata_annotations" {
  source = "../metadata_annotations"
  cloud_vendor = var.metadata_cloud_vendor
  k8s = var.metadata_k8s
  node_os = var.metadata_node_os
}
