# Creates the Ansible inventory files for an OpenStack based Stackable cluster

terraform {
  required_version = ">= 0.15, < 2.0.0"
}

variable "nodes" {
  description = "instance resource representing custom nodes" 
}

variable "orchestrator" {
  description = "instance resource representing orchestrator node" 
}

variable "cluster_private_key_filename" {
  type = string
  description = "master keyfile"
}

variable "cluster_ip" {
  type = string
  description = "Public IP of cluster"
}

variable "edge_node_internal_ip" {
  type = string
  description = "internal IP of edge node"
}

variable "stackable_user" {
  type = string
  description = "User for Stackable stuff"
}

variable "stackable_user_home" {
  type = string
  description = "Home directory of Stackable user"
}

# variable file for Ansible
resource "local_file" "ansible-variables" {
  filename = "inventory/group_vars/all/all.yml"
  content = templatefile("${path.module}/templates/ansible-variables.tpl",
    {
      ssh_client_keys = can(yamldecode(file("cluster.yaml"))["publicKeys"]) ? [
        for k in yamldecode(file("cluster.yaml"))["publicKeys"]: 
          k
      ] : []
    }
  )
  file_permission = "0440"
}

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "inventory/inventory"
  content = templatefile("${path.module}/templates/ansible-inventory.tpl",
    {
      stackable_user = var.stackable_user
      stackable_user_home = var.stackable_user_home
      domain = yamldecode(file("cluster.yaml"))["domain"]
      nodes = var.nodes
      cluster_ip = var.cluster_ip
      edge_node_internal_ip = var.edge_node_internal_ip
      orchestrator = var.orchestrator
      ssh_key_private_path = var.cluster_private_key_filename
      wireguard = can(yamldecode(file("cluster.yaml"))["spec"]["wireguard"]) ? yamldecode(file("cluster.yaml"))["spec"]["wireguard"] : false
    }
  )
  file_permission = "0440"
} 

