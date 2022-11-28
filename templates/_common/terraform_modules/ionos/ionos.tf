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
  labels = can(yamldecode(file("cluster.yaml"))["metadata"]["labels"]) ? yamldecode(file("cluster.yaml"))["metadata"]["labels"] : {}
  labels_string = join(", ", [ for key, value in local.labels : "${key}:${value}" ])
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
  datacenter_description        = local.labels_string
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

module "stackable_client_script" {
  source                        = "../stackable_client_script"
  nodes                         = [for node in module.ionos_protected_nodes.protected_nodes : 
    { name = node.name, ip = node.primary_ip }
  ]
  orchestrator_ip               = module.ionos_protected_nodes.orchestrator.primary_ip
  cluster_ip                    = module.ionos_edge_node.cluster_ip
  ssh-username                  = "root"
}

module "ssh_config" {
  source                        = "../ssh_config"
  nodes                         = [for node in module.ionos_protected_nodes.protected_nodes : 
    { name = node.name, ip = node.primary_ip }
  ]
  orchestrator_ip               = module.ionos_protected_nodes.orchestrator.primary_ip
  cluster_ip                    = module.ionos_edge_node.cluster_ip
  ssh-username                  = "root"
}

module "stackable_service_definitions" {
  source = "../stackable_service_definitions"
}
