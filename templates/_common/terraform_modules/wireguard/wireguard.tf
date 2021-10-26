terraform {
  required_version = ">= 0.15, < 2.0.0"
}

variable "server_config_filename" {
  type = string
}

variable "client_config_base_path" {
  type = string
}

variable "allowed_ips" {
  type = list(string)
}

variable "endpoint_ip" {
  type = string
}

# wireguard configfile for edge node
resource "local_file" "wireguard_nat_config" {
  filename = var.server_config_filename
  file_permission = "0440"
  content = templatefile("${path.module}/templates/wg.conf.tpl",
    {
      wg_nat_private_key = yamldecode(file("wireguard.yaml"))["server"]["privateKey"]
      wg_client_public_keys = [ for client in yamldecode(file("wireguard.yaml"))["clients"]: client.publicKey ]
    }
  )
}

# wireguard configfile for clients
resource "local_file" "wireguard_client_config" {
  count = length(yamldecode(file("wireguard.yaml"))["clients"])
  filename = "${var.client_config_base_path}/${count.index + 1}/wg.conf"
  file_permission = "0440"
  content = templatefile("${path.module}/templates/wg-client.conf.tpl",
    {
      index = count.index
      client_private_key = yamldecode(file("wireguard.yaml"))["clients"][count.index]["privateKey"]
      allowed_ips = var.allowed_ips
      wg_server_public_key = yamldecode(file("wireguard.yaml"))["server"]["publicKey"]
      endpoint_ip = var.endpoint_ip
    }
  )
}


