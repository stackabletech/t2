terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "6.3.1"
    }
  }
}

variable "cluster_id" {
  description = "ID of the cluster"
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "cluster_ip" {
  type = string
}

variable "edge_node_internal_ip" {
  type = string
}

variable "nat_gateway_ip" {
  type = string
}

variable "node_configuration" {
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

variable "location" {
  type = string
}

variable "domain" {
  type = string
  description = "Network domain of the internal network"
}

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "inventory/inventory"
  content = templatefile("${path.module}/templates/ansible-inventory.tpl",
    {
      cluster_id = var.cluster_id
      cluster_name = var.cluster_name
      domain = var.domain
      k8s_version = can(yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"]) ? yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"] : ""
      stackable_user = "root"
      stackable_user_home = "/root/"
      cluster_ip = var.cluster_ip
      nodes = var.protected_nodes
      node_configuration = var.node_configuration
      edge_node_internal_ip = var.edge_node_internal_ip
      orchestrator = var.orchestrator
      ssh_key_private_path = var.cluster_private_key_filename
      wireguard = can(yamldecode(file("cluster.yaml"))["spec"]["wireguard"]) ? yamldecode(file("cluster.yaml"))["spec"]["wireguard"] : false
      nat_gateway_ip = var.nat_gateway_ip
      location = replace(var.location, "/", "_")
    }
  )
  file_permission = "0440"
} 

module "ansible_variables_public_ssh_keys" {
  source                        = "../common_ansible_variables_public_ssh_keys"
}

