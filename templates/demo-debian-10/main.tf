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

# information on all the (protected) nodes (collected from the cluster.yaml)
locals {
  nodes = { for node in flatten([
    for type, definition in yamldecode(file("cluster.yaml"))["spec"]["nodes"] : [
      for i in range(1, definition.numberOfNodes + 1): {
        name = "${type}-${i}" 
        numberOfCores = definition.numberOfCores
        memoryMb = definition.memoryMb
        diskType = definition.diskType
        diskSizeGb = definition.diskSizeGb
        agent = can(definition.agent) ? definition.agent : true
      }
    ]
  ]): node.name => node }
  datacenter_location = yamldecode(file("cluster.yaml"))["spec"]["region"]
  datacenter_description = yamldecode(file("cluster.yaml"))["metadata"]["description"]
}

module "master_keypair" {
  source      = "./terraform_modules/master_keypair"
  filename    = "${path.module}/cluster_key"
}

module "stackable_package_versions_debian" {
  source = "./terraform_modules/stackable_package_versions_debian"
}

module "ionos_network" {
  source                        = "./terraform_modules/ionos_network"
  datacenter_name               = var.cluster_name
  datacenter_location           = local.datacenter_location
  datacenter_description        = local.datacenter_description
}

module "ionos_edge_node" {
  source                        = "./terraform_modules/ionos_edge_node"
  datacenter                    = module.ionos_network.datacenter
  external_lan                  = module.ionos_network.external_lan
  internal_lan                  = module.ionos_network.internal_lan
  cluster_public_key_filename   = "${path.module}/cluster_key.pub"
  cluster_private_key_filename  = "${path.module}/cluster_key"
}

module "ionos_protected_nodes" {
  source                        = "./terraform_modules/ionos_protected_nodes"
  datacenter                    = module.ionos_network.datacenter
  internal_lan                  = module.ionos_network.internal_lan
  cluster_ip                    = module.ionos_edge_node.cluster_ip
  nodes                         = local.nodes
  os_name                       = "Debian"
  os_version                    = "10-server"
  cluster_public_key_filename   = "${path.module}/cluster_key.pub"
  cluster_private_key_filename  = "${path.module}/cluster_key"
}

module "ionos_inventory" {
  source                        = "./terraform_modules/ionos_inventory"
  cluster_ip                    = module.ionos_edge_node.cluster_ip
  edge_node_internal_ip         = module.ionos_edge_node.edge_node_internal_ip
  node_data                     = local.nodes
  protected_nodes               = module.ionos_protected_nodes.protected_nodes
  orchestrator                  = module.ionos_protected_nodes.orchestrator
  cluster_public_key_filename   = "${path.module}/cluster_key.pub"
  cluster_private_key_filename  = "${path.module}/cluster_key"
}

module "stackable_client_script" {
  source                        = "./terraform_modules/stackable_client_script"
  nodes                         = [for node in module.ionos_protected_nodes.protected_nodes : 
    { name = node.name, ip = node.primary_ip }
  ]
  orchestrator_ip               = module.ionos_protected_nodes.orchestrator.primary_ip
  cluster_ip                    = module.ionos_edge_node.cluster_ip
  ssh-username                  = "root"
}

module "stackable_service_definitions" {
  source = "./terraform_modules/stackable_service_definitions"
}

module "wireguard" {
  count                     = can(yamldecode(file("cluster.yaml"))["spec"]["wireguard"]) ? (yamldecode(file("cluster.yaml"))["spec"]["wireguard"] ? 1 : 0) : 0
  source                    = "./terraform_modules/wireguard"
  server_config_filename    = "ansible_roles/files/wireguard_server.conf"
  client_config_base_path   = "resources/wireguard-client-config"
  allowed_ips               = concat([ for node in module.ionos_protected_nodes.protected_nodes: node.primary_ip ], [module.ionos_protected_nodes.orchestrator.primary_ip])
  endpoint_ip               = module.ionos_edge_node.cluster_ip
}

