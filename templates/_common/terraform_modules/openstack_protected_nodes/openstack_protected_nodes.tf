# Creates the protected nodes (= nodes not directly accessible from the outside world) of an OpenStack based Stackable cluster

terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "1.43.0"
    }
  }
}

variable "cluster_name" {
  type = string
  description = "name of the cluster"
}

variable "cluster_ip" {
  type = string
  description = "public IP of the cluster"
}

variable "network_name" {
  type = string
  description = "name of the cluster's network"
}

variable "keypair_name" {
  type = string
  description = "name of the keypair to be used to access the machine(s) created in this module"
}

variable "cluster_private_key_filename" {
  type = string
  description = "master keyfile"
}

variable "stackable_user" {
  type = string
  description = "non-root user for Stackable"
}

variable "security_groups" {
  type = list
  description = "List of security groups for the bastion host"
}

variable "network_ready_flag" {
  description = "resource as a flag to indicate that the network is ready to be used"
}

# list of all the nodes of the different types
locals {
  nodes = flatten([
    for type, definition in yamldecode(file("cluster.yaml"))["spec"]["nodes"] : [
      for i in range(1, definition.numberOfNodes + 1): {
        name = "${type}-${i}" 
        flavorName = can(definition.openstackFlavorName) ? definition.openstackFlavorName : "2C-4GB-20GB"
        agent = can(definition.agent) ? definition.agent : true
      }
    ]
  ])
}

# Create the orchestrator compute instance
resource "openstack_compute_instance_v2" "orchestrator" {
  depends_on      = [ var.network_ready_flag ]
  name            = "${var.cluster_name}-orchestrator"
  image_id        = "3ecdee9c-241c-4913-acf0-12731f73d2b6"  # CentOS 8
  flavor_name     = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["openstackFlavorName"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["openstackFlavorName"] : "8C-16GB-60GB"
  key_pair        = var.keypair_name
  security_groups = var.security_groups

  network {
    name = var.network_name
  }
}

# Create the cluster-specific nodes as compute instances
resource "openstack_compute_instance_v2" "node" {
  depends_on      = [ var.network_ready_flag ]
  count           = length(local.nodes)
  name            = "${var.cluster_name}-${local.nodes[count.index].name}"
  image_id        = "3ecdee9c-241c-4913-acf0-12731f73d2b6"  # CentOS 8
  flavor_name     = local.nodes[count.index].flavorName
  key_pair        = "${var.cluster_name}-master-key"
  security_groups = var.security_groups

  network {
    name = "${var.cluster_name}-network"
  }

  metadata = {
    "hostname" = local.nodes[count.index].name
    "has_agent" = local.nodes[count.index].agent
  }
}

# script to ssh into orchestrator via ssh proxy (aka jump host)
module "ssh_script_orchestrator" {
  source                        = "../common_ssh_script_protected_node"
  cluster_ip                    = var.cluster_ip
  node_ip                       = openstack_compute_instance_v2.orchestrator.access_ip_v4
  user                          = var.stackable_user
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-orchestrator.sh"
}

# script to ssh into nodes via ssh proxy (aka jump host)
module "ssh_script_nodes" {
  count                         = length(local.nodes)
  source                        = "../common_ssh_script_protected_node"
  cluster_ip                    = var.cluster_ip
  node_ip                       = element(openstack_compute_instance_v2.node.*.access_ip_v4, count.index)
  user                          = var.stackable_user
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-${local.nodes[count.index].name}.sh"
}

output "orchestrator" {
  value = openstack_compute_instance_v2.orchestrator
  description = "Orchestrator node as resource"
}

output "nodes" {
  value = openstack_compute_instance_v2.node
  description = "Protected nodes as list of resources"
}
