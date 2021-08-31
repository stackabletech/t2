# Creates a script to SSH into a protected node via the jump host

terraform {
  required_version = ">= 0.15, < 2.0.0"
}

variable "cluster_ip" {
  type = string
  description = "public IP of the cluster"
}

variable "node_ip" {
  type = string
  description = "private IP of the node in the cluster"
}

variable "user" {
  type = string
  description = "username on remote host"
}

variable "cluster_private_key_filename" {
  type = string
  description = "master keyfile"
}

variable "filename" {
  type = string
  description = "file name of the script file to be generated"
}

# script to ssh into bastion host
resource "local_file" "protected-node-ssh-script" {
  filename = var.filename
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-protected-node-script.tpl",
    {
      cluster_ip = var.cluster_ip
      node_ip = var.node_ip
      user = var.user
      ssh_key_private_path = var.cluster_private_key_filename
    }
  )
}
