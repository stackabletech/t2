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

variable "bastion_host_internal_ip" {
  type = string
  description = "internal IP of bastion host"
}

variable "stackable_user" {
  type = string
  description = "non-root user for Stackable"
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
      domain = yamldecode(file("cluster.yaml"))["domain"]
      nodes = var.nodes
      cluster_ip = var.cluster_ip
      bastion_host_internal_ip = var.bastion_host_internal_ip
      orchestrator = var.orchestrator
      ssh_key_private_path = var.cluster_private_key_filename
      wireguard = can(yamldecode(file("cluster.yaml"))["spec"]["wireguard"]) ? yamldecode(file("cluster.yaml"))["spec"]["wireguard"] : false
    }
  )
  file_permission = "0440"
} 

