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

variable "network_ready_flag" {
  description = "resource as a flag to indicate that the network is ready to be used"
}

resource "openstack_compute_instance_v2" "nat" {
  depends_on      = [ var.network_ready_flag ]
  name            = "${var.cluster_name}-nat"
  image_id        = "3ecdee9c-241c-4913-acf0-12731f73d2b6"  # CentOS 8
  flavor_name     = "2C-2GB-20GB"
  key_pair        = var.keypair_name
  security_groups = ["default"]


  network {
    name = var.network_name
  }
}

resource "openstack_compute_floatingip_associate_v2" "cluster_ip_association_to_bastion_host" {
  floating_ip = var.cluster_ip
  instance_id = openstack_compute_instance_v2.nat.id
}

# script to ssh into bastion host
resource "local_file" "bastion-host-ssh-script" {
  filename = "ssh-bastion-host.sh"
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-bastion-host-script.tpl",
    {
      node_ip = var.cluster_ip
      ssh_key_private_path = var.cluster_private_key_filename
      stackable_user = var.stackable_user
    }
  )
}

output "bastion_host_internal_ip" {
  value = openstack_compute_instance_v2.nat.access_ip_v4
}