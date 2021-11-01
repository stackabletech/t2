# Creates an HCloud network/subnet for a cluster to be built.

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

resource "hcloud_server" "edge" {
  name        = "${var.cluster_name}-edge"
  server_type = "cx11"
  image       = var.os_image
  location    = var.location
  ssh_keys    = [ var.keypair.id ]

  network {
    network_id = var.network.id
  }

  depends_on = [
    var.network,
    var.subnet
  ]
}

# script to ssh into edge node
module "edge_node_ssh_script" {
  source                        = "../common_ssh_script_edge_node"
  ip                            = hcloud_server.edge.ipv4_address
  user                          = var.stackable_user
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-edge.sh"
}

output "edge_node_internal_ip" {
  value = element(hcloud_server.edge.network[*].ip, 0)
  description = "The internal IP of the edge node"
}

output "cluster_ip" {
  value = hcloud_server.edge.ipv4_address
  description = "The public IP of the edge node, which is the cluster's IP"
}