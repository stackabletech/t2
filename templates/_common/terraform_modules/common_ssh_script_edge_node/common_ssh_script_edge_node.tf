# Creates a script to SSH into the edge node

terraform {
  required_version = ">= 0.15, < 2.0.0"
}

variable "ip" {
  type = string
  description = "public IP of the cluster"
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

# script to ssh into edge_node
resource "local_file" "edge-node-ssh-script" {
  filename = var.filename
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-edge-node-script.tpl",
    {
      ip = var.ip
      user = var.user
      ssh_key_private_path = var.cluster_private_key_filename
    }
  )
}
