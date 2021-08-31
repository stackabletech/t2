# Creates a script to SSH into the bastion host

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

# script to ssh into bastion host
resource "local_file" "bastion-host-ssh-script" {
  filename = var.filename
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-bastion-host-script.tpl",
    {
      ip = var.ip
      user = var.user
      ssh_key_private_path = var.cluster_private_key_filename
    }
  )
}
