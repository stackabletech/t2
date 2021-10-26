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

variable "cluster_ip" {
  type = string
}

variable "edge_node_internal_ip" {
  type = string
}

variable "node_data" {
}

variable "protected_nodes" {
}

variable "orchestrator" {
}

variable "cluster_public_key_filename" {
  type = string
}

variable "cluster_private_key_filename" {
  type = string
}

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "inventory/inventory"
  content = templatefile("${path.module}/templates/ansible-inventory.tpl",
    {
      domain = yamldecode(file("cluster.yaml"))["domain"]
      stackable_user = "root"
      stackable_user_home = "/root/"
      cluster_ip = var.cluster_ip
      nodes = var.protected_nodes
      node_data = var.node_data
      edge_node_internal_ip = var.edge_node_internal_ip
      orchestrator = var.orchestrator
      ssh_key_private_path = var.cluster_private_key_filename
      wireguard = can(yamldecode(file("cluster.yaml"))["spec"]["wireguard"]) ? yamldecode(file("cluster.yaml"))["spec"]["wireguard"] : false
    }
  )
  file_permission = "0440"
} 

