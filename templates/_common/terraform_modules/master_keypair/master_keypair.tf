terraform {
  required_version = "~> 0.15"
}

variable "filename" {
  type = string
}

resource "tls_private_key" "cluster_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "cluster_private_key" { 
  filename = "${var.filename}"
  content = tls_private_key.cluster_key.private_key_pem
  file_permission = "0400"
}

resource "local_file" "cluster_public_key" { 
  filename = "${var.filename}.pub"
  content = tls_private_key.cluster_key.public_key_openssh
  file_permission = "0440"
}
