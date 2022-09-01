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

variable "datacenter" {
}

variable "internal_lan" {
}

variable "cluster_ip" {
  type = string
}

variable "os_name" {
  type = string
}

variable "os_version" {
  type = string
}

variable "node_configuration" {
}

variable "cluster_public_key_filename" {
  type = string
}

variable "cluster_private_key_filename" {
  type = string
}

# list of all node names to iterate over
locals {
  nodenames = [ for node in var.node_configuration: node.name ]
}

data "ionoscloud_image" "os_image_protected_node" {
  name     = var.os_name
  version  = var.os_version
  type     = "HDD"
  location = var.datacenter.location
}

resource "ionoscloud_server" "orchestrator" {
  name = "orchestrator"
  datacenter_id = var.datacenter.id
  cores = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["numberOfCores"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["numberOfCores"] : 4
  ram = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["memoryMb"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["memoryMb"] : 8192
  cpu_family = can(yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"]) ? yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"] : null
  availability_zone = "ZONE_1"

  image_name = data.ionoscloud_image.os_image_protected_node.name
  ssh_key_path = [ var.cluster_public_key_filename ]

  volume {
    name = "orchestrator-storage"
    size = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskSizeGb"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskSizeGb"] : 50
    disk_type = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskType"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskType"] : "HDD"
  }

  nic {
    name = "orchestrator-internal-nic"
    lan = var.internal_lan.id
    dhcp = true
    firewall_active = false
  }
}

# nodes (servers)
resource "ionoscloud_server" "node" {
  count = length(local.nodenames)
  name = var.node_configuration[local.nodenames[count.index]].name
  datacenter_id = var.datacenter.id
  cores = var.node_configuration[local.nodenames[count.index]].numberOfCores
  ram = var.node_configuration[local.nodenames[count.index]].memoryMb
  cpu_family = can(yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"]) ? yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"] : null
  availability_zone = "ZONE_1"

  image_name = data.ionoscloud_image.os_image_protected_node.name
  ssh_key_path = [ var.cluster_public_key_filename ]

  volume {
    name = "${var.node_configuration[local.nodenames[count.index]].name}-storage"
    size = var.node_configuration[local.nodenames[count.index]].diskSizeGb
    disk_type = var.node_configuration[local.nodenames[count.index]].diskType
  }

  nic {
    name = "${var.node_configuration[local.nodenames[count.index]].name}-internal-nic"
    lan = var.internal_lan.id
    dhcp = true
    firewall_active = false
  }
}

# script to ssh into orchestrator using edge node as jump host
module "ssh_script_orchestrator" {
  source                        = "../common_ssh_script_protected_node"
  cluster_ip                    = var.cluster_ip
  node_ip                       = ionoscloud_server.orchestrator.primary_ip
  user                          = "root"
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-orchestrator.sh"
}

# script to ssh into nodes using edge node as jump host
module "ssh_script_nodes" {
  count                         = length(local.nodenames)
  source                        = "../common_ssh_script_protected_node"
  cluster_ip                    = var.cluster_ip
  node_ip                       = ionoscloud_server.node[count.index].primary_ip
  user                          = "root"
  cluster_private_key_filename  = var.cluster_private_key_filename
  filename                      = "ssh-${var.node_configuration[local.nodenames[count.index]].name}.sh"
}

output "orchestrator" {
  value = ionoscloud_server.orchestrator
}

output "protected_nodes" {
  value = ionoscloud_server.node
}