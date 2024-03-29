terraform {
  required_version = ">= 0.15, < 2.0.0"
}

variable "nodes" {
  description = "AWS instance resource representing custom nodes" 
}

variable "orchestrator" {
  description = "AWS instance resource representing orchestrator node" 
}

variable "cluster_private_key_filename" {
  type = string
  description = "master keyfile"
}

variable "cluster_ip" {
  type = string
  description = "Public IP of cluster"
}

variable "stackable_user" {
  type = string
  description = "User for Stackable stuff"
}

variable "stackable_user_home" {
  type = string
  description = "Home directory of Stackable user"
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
      stackable_user = var.stackable_user
      stackable_user_home = var.stackable_user_home
      domain = var.domain
      k8s_requested_version = can(yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"]) ? yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"] : ""
      nodes = var.nodes
      cluster_ip = var.cluster_ip
      orchestrator = var.orchestrator
      ssh_key_private_path = var.cluster_private_key_filename
    }
  )
  file_permission = "0440"
}
