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

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "os_image" {
  description = "Image of the OS for the node, e.g. centos-8"
  type        = string
}

# collect configuration information from cluster.yaml
locals {

  node_configuration = { for node in flatten([
    for type, definition in yamldecode(file("cluster.yaml"))["spec"]["nodes"] : [
      for i in range(1, definition.numberOfNodes + 1): {
        name = "${type}-${i}" 
        serverType = can(definition.serverType) ? definition.serverType : "cx21"
        agent = can(definition.agent) ? definition.agent : true
      }
    ]
  ]): node.name => node }

  location = can(yamldecode(file("cluster.yaml"))["spec"]["location"]) ? yamldecode(file("cluster.yaml"))["spec"]["location"] : "nbg1"
}

locals {
  stackable_user = "root"
  stackable_user_home = "/root/"
}

# Keypair (as files on disk where Terraform is executed)
module "master_keypair" {
  source      = "../master_keypair"
  filename    = "cluster_key"
}

# Keypair (as HCloud resource)
resource "hcloud_ssh_key" "master_keypair" {
  name       = "${var.cluster_name}-master-key"
  public_key = module.master_keypair.public_key_openssh
}

# Creates the subnet for this cluster
module "hcloud_network" {
  source                        = "../hcloud_network"
  cluster_name                  = var.cluster_name
}

# Creates the edge node for this cluster
module "hcloud_edge_node" {
  source                        = "../hcloud_edge_node"
  cluster_name                  = var.cluster_name
  keypair                       = hcloud_ssh_key.master_keypair
  cluster_private_key_filename  = "cluster_key"
  network                       = module.hcloud_network.network
  subnet                        = module.hcloud_network.subnet
  stackable_user                = local.stackable_user
  location                      = local.location
  os_image                      = var.os_image
}

# Creates the protected nodes for this cluster
module "hcloud_protected_nodes" {
  source                        = "../hcloud_protected_nodes"
  cluster_name                  = var.cluster_name
  keypair                       = hcloud_ssh_key.master_keypair
  cluster_private_key_filename  = "cluster_key"
  network                       = module.hcloud_network.network
  subnet                        = module.hcloud_network.subnet
  stackable_user                = local.stackable_user
  node_configuration            = local.node_configuration
  cluster_ip                    = module.hcloud_edge_node.cluster_ip
  location                      = local.location
  os_image                      = var.os_image
}

# Creates the Ansible inventory file(s) for this cluster
module "hcloud_inventory" {
  source                        = "../hcloud_inventory"
  orchestrator                  = module.hcloud_protected_nodes.orchestrator
  nodes                         = module.hcloud_protected_nodes.nodes
  cluster_private_key_filename  = "cluster_key"
  cluster_ip                    = module.hcloud_edge_node.cluster_ip
  edge_node_internal_ip         = module.hcloud_edge_node.edge_node_internal_ip
  stackable_user                = local.stackable_user
  stackable_user_home           = local.stackable_user_home
}

#module "stackable_client_script" {
#  source                        = "../stackable_client_script"
#  nodes                         = [for node in module.ionos_protected_nodes.protected_nodes : 
#    { name = node.name, ip = node.primary_ip }
#  ]
#  orchestrator_ip               = module.ionos_protected_nodes.orchestrator.primary_ip
#  cluster_ip                    = module.ionos_edge_node.cluster_ip
#  ssh-username                  = "root"
#}
#
#module "stackable_service_definitions" {
#  source = "../stackable_service_definitions"
#}
#
#module "wireguard" {
#  count                     = can(yamldecode(file("cluster.yaml"))["spec"]["wireguard"]) ? (yamldecode(file("cluster.yaml"))["spec"]["wireguard"] ? 1 : 0) : 0
#  source                    = "../wireguard"
#  server_config_filename    = "ansible_roles/files/wireguard_server.conf"
#  client_config_base_path   = "resources/wireguard-client-config"
#  allowed_ips               = concat([ for node in module.ionos_protected_nodes.protected_nodes: node.primary_ip ], [module.ionos_protected_nodes.orchestrator.primary_ip])
#  endpoint_ip               = module.ionos_edge_node.cluster_ip
#}

