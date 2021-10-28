# Creates the protected nodes (= nodes not directly accessible from the outside world) of a Hetzner Cloud based Stackable cluster

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
  type = string
  description = "name of the cluster"
}

variable "cluster_ip" {
  type = string
  description = "public IP of the cluster"
}

variable "keypair" {
  description = "keypair to use for the servers that are created"
}

variable "network" {
  description = "HCloud network to attach the edge node to."
}

variable "subnet" {
  description = "HCloud subnet to attach the edge node to."
}

variable "stackable_user" {
  type = string
  description = "non-root user for Stackable"
}

variable "cluster_private_key_filename" {
  type = string
  description = "master keyfile"
}

variable "os_image" {
  description = "Image of the OS for the node, e.g. centos-8"
  type        = string
}

variable "location" {
  description = "Location of the node, e.g. nbg1"
  type        = string
}


variable "node_configuration" {
}

# list of all node names to iterate over
locals {
  nodenames = [ for node in var.node_configuration: node.name ]
}

# Create the orchestrator compute instance
resource "hcloud_server" "orchestrator" {
  name        = "${var.cluster_name}-orchestrator"
  server_type = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["serverType"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["serverType"] : "cx41"
  image       = var.os_image
  location    = var.location
  ssh_keys    = [ var.keypair.id ]

  network {
    network_id = var.network.id
    ip         = "10.0.1.6"
  }

  depends_on = [
    var.network,
    var.subnet
  ]
}

# Create the cluster-specific nodes as compute instances
resource "hcloud_server" "node" {
  count       = length(local.nodenames)
  name        = "${var.cluster_name}-${var.node_configuration[local.nodenames[count.index]].name}"
  server_type = var.node_configuration[local.nodenames[count.index]].serverType
  image       = var.os_image
  location    = var.location
  ssh_keys    = [ var.keypair.id ]

  network {
    network_id = var.network.id
    ip         = "10.0.1.${count.index + 10}"
  }

  depends_on = [
    var.network,
    var.subnet
  ]
}

# script to ssh into orchestrator via ssh proxy (aka jump host)
module "ssh_script_orchestrator" {
  source                        = "../common_ssh_script_protected_node"
  cluster_ip                    = var.cluster_ip
  node_ip                       = element(hcloud_server.orchestrator.network[*].ip, 0)
  user                          = var.stackable_user
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-orchestrator.sh"
}

# script to ssh into nodes via ssh proxy (aka jump host)
module "ssh_script_nodes" {
  count                         = length(local.nodenames)
  source                        = "../common_ssh_script_protected_node"
  cluster_ip                    = var.cluster_ip
  node_ip                       = element(element(hcloud_server.node.*.network[*].ip, 0), count.index)
  user                          = var.stackable_user
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-${var.node_configuration[local.nodenames[count.index]].name}.sh"
}

output "orchestrator" {
  value = hcloud_server.orchestrator
  description = "Orchestrator node as resource"
}

output "nodes" {
  value = hcloud_server.orchestrator.node
  description = "Protected nodes as list of resources"
}
