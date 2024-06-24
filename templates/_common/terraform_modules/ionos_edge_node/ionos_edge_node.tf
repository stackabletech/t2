terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "6.4.18"
    }
  }
}

variable "datacenter" {
}

variable "external_lan" {
}

variable "internal_lan" {
}

variable "cluster_public_key_filename" {
  type = string
}

variable "cluster_private_key_filename" {
  type = string
}

data "ionoscloud_image" "os_image_edge_node" {
  name     = "rocky"
  version  = "8.6-GenericCloud-20220702"
  type     = "HDD"
  location = var.datacenter.location
}

# edge node
resource "ionoscloud_server" "edge" {
  name = "edge"
  datacenter_id = var.datacenter.id
  cores = 2
  ram = 1024
  cpu_family = can(yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"]) ? yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"] : null
  availability_zone = "ZONE_1"

  image_name = data.ionoscloud_image.os_image_edge_node.name
  ssh_key_path = [ var.cluster_public_key_filename ]

  volume {
    name = "edge-storage"

    size = 15
    disk_type = "SSD"
  }

  nic {
    name = "edge-external-nic"
    lan = var.external_lan.id
    dhcp = true
    firewall_active = false
  }
}

# internal network interface for edge_node
resource "ionoscloud_nic" "edge_internal" {
  name = "edge-internal-nic"
  datacenter_id = var.datacenter.id
  lan = var.internal_lan.id
  server_id = ionoscloud_server.edge.id
  dhcp = true
  firewall_active = false
}

# script to ssh into edge node
module "edge_node_ssh_script" {
  source                        = "../common_ssh_script_edge_node"
  ip                            = ionoscloud_server.edge.primary_ip
  user                          = "root"
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-edge.sh"
}

output "cluster_ip" {
  value = ionoscloud_server.edge.primary_ip
}

output "edge_node_internal_ip" {
  value = ionoscloud_nic.edge_internal.ips[0]
}