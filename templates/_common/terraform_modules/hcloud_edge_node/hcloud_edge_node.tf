# Creates an HCloud network/subnet for a cluster to be built.

terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      version = "1.35.1"
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

variable "location" {
  description = "Location of the node, e.g. nbg1"
  type        = string
}

resource "hcloud_firewall" "edge_node" {
  name = "${var.cluster_name}-edge-node-firewall"
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
  rule {
    direction = "in"
    protocol  = "udp"
    port      = "52888"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "any"
    source_ips = [
      "10.0.0.0/16"
    ]
  }
  rule {
    direction = "in"
    protocol  = "udp"
    port      = "any"
    source_ips = [
      "10.0.0.0/16"
    ]
  }
}

resource "hcloud_server" "edge" {
  name        = "${var.cluster_name}-edge"
  server_type = "cx11"
  image       = "centos-stream-9"
  location    = var.location
  ssh_keys    = [ var.keypair.id ]

  network {
    network_id = var.network.id
  }

  firewall_ids = [ hcloud_firewall.edge_node.id ]

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