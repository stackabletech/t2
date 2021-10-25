# Creates an edge node for an OpenStack cluster

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
  description = "List of security groups for the edge node"
}

variable "network_ready_flag" {
  description = "resource as a flag to indicate that the network is ready to be used"
}

# edge node compute instance
resource "openstack_compute_instance_v2" "edge" {
  depends_on      = [ var.network_ready_flag ]
  name            = "${var.cluster_name}-edge"
  image_id        = "3ecdee9c-241c-4913-acf0-12731f73d2b6"  # CentOS 8
  flavor_name     = "2C-2GB-20GB"
  key_pair        = var.keypair_name
  security_groups = var.security_groups

  network {
    name = var.network_name
  }
}

# associate public IP of the cluster to the edge node
resource "openstack_compute_floatingip_associate_v2" "cluster_ip_association_to_edge_node" {
  floating_ip = var.cluster_ip
  instance_id = openstack_compute_instance_v2.edge.id
}

# script to ssh into edge node
module "edge_node_ssh_script" {
  source                        = "../common_ssh_script_edge_node"
  ip                            = var.cluster_ip
  user                          = var.stackable_user
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-edge.sh"
}

output "edge_node_internal_ip" {
  value = openstack_compute_instance_v2.edge.access_ip_v4
  description = "The internal IP of the edge node"
}