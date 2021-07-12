terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "5.0.4"
    }
  }
}

variable "os_name" {
  type = string
}

variable "os_version" {
  type = string
}

variable "datacenter_name" {
  type = string
}

variable "cluster_public_key_filename" {
  type = string
}

variable "cluster_private_key_filename" {
  type = string
}

# list of all the nodes of the different types
locals {
  nodes = flatten([
    for type, definition in yamldecode(file("cluster.yaml"))["spec"]["nodes"] : [
      for i in range(1, definition.numberOfNodes + 1): {
        name = "${type}-${i}" 
        numberOfCores = definition.numberOfCores
        memoryMb = definition.memoryMb
        diskType = definition.diskType
        diskSizeGb = definition.diskSizeGb
        agent = can(definition.agent) ? definition.agent : true
      }
    ]
  ])
}

# list of all the service definitions
locals {
  service_definitions = can(yamldecode(file("cluster.yaml"))["services"]) ? [
    for n, c in yamldecode(file("cluster.yaml"))["services"]: {
      name = n
      content = c 
    }
  ] : []
}

data "ionoscloud_image" "os_image" {
  name     = var.os_name
  version  = var.os_version
  type     = "HDD"
  location = yamldecode(file("cluster.yaml"))["spec"]["region"]
}

# (virtual) Datacenter
resource "ionoscloud_datacenter" "datacenter" {
  name = var.datacenter_name
  location = yamldecode(file("cluster.yaml"))["spec"]["region"]
  description = yamldecode(file("cluster.yaml"))["metadata"]["description"]
}

# Internet facing lan
resource "ionoscloud_lan" "external" {
  name = "External Network"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  public = true
}

# Private lan
resource "ionoscloud_lan" "internal" {
  name = "Internal Network"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  public = false
}

# NAT Server (aka "bastion host")
resource "ionoscloud_server" "nat" {
  name = "nat"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  cores = 2
  ram = 1024
  cpu_family = can(yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"]) ? yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"] : null
  availability_zone = "ZONE_1"

  image_name = data.ionoscloud_image.os_image.name
  ssh_key_path = [ var.cluster_public_key_filename ]

  volume {
    name = "nat-storage"

    size = 15
    disk_type = "SSD"
  }

  nic {
    lan = ionoscloud_lan.external.id
    dhcp = true
    firewall_active = false
  }
}

# file containing IP address of bastion host.
resource "local_file" "ipv4_file" {
  filename = "ipv4"
  content = ionoscloud_server.nat.primary_ip
  file_permission = "0440"
}

# internal network interface for bastion host
resource "ionoscloud_nic" "nat_internal" {
  datacenter_id = ionoscloud_datacenter.datacenter.id
  lan = ionoscloud_lan.internal.id
  server_id = ionoscloud_server.nat.id

  dhcp = true
  firewall_active = false
}

resource "ionoscloud_server" "orchestrator" {
  name = "orchestrator"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  cores = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["numberOfCores"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["numberOfCores"] : 4
  ram = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["memoryMb"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["memoryMb"] : 8192
  cpu_family = can(yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"]) ? yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"] : null
  availability_zone = "ZONE_1"

  image_name = data.ionoscloud_image.os_image.name
  ssh_key_path = [ var.cluster_public_key_filename ]

  volume {
    name = "orchestrator-storage"
    size = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskSizeGb"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskSizeGb"] : 50
    disk_type = can(yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskType"]) ? yamldecode(file("cluster.yaml"))["spec"]["orchestrator"]["diskType"] : "HDD"
  }

  nic {
    name = "orchestrator-internal-nic"
    lan = ionoscloud_lan.internal.id
    dhcp = true
    firewall_active = false
  }
}

# nodes (servers)
resource "ionoscloud_server" "node" {
  count = length(local.nodes)
  name = local.nodes[count.index].name
  datacenter_id = ionoscloud_datacenter.datacenter.id
  cores = local.nodes[count.index].numberOfCores
  ram = local.nodes[count.index].memoryMb
  cpu_family = can(yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"]) ? yamldecode(file("cluster.yaml"))["spec"]["cpuFamily"] : null
  availability_zone = "ZONE_1"

  image_name = data.ionoscloud_image.os_image.name
  ssh_key_path = [ var.cluster_public_key_filename ]

  volume {
    name = "${local.nodes[count.index].name}-storage"
    size = local.nodes[count.index].diskSizeGb
    disk_type = local.nodes[count.index].diskType
  }

  nic {
    name = "${local.nodes[count.index].name}-internal-nic"
    lan = ionoscloud_lan.internal.id
    dhcp = true
    firewall_active = false
  }
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
      domain = yamldecode(file("cluster.yaml"))["domain"]
      nodes = ionoscloud_server.node
      nodes_has_agent = [ for node in local.nodes : node.agent ]
      nat_public_ip = ionoscloud_server.nat.primary_ip
      nat_internal_ip = ionoscloud_nic.nat_internal.ips[0]
      orchestrator = ionoscloud_server.orchestrator
      ssh_key_private_path = var.cluster_private_key_filename
      wireguard = can(yamldecode(file("cluster.yaml"))["spec"]["wireguard"]) ? yamldecode(file("cluster.yaml"))["spec"]["wireguard"] : true
    }
  )
  file_permission = "0440"
} 

# service definition files
resource "local_file" "service-definition" {
  count = length(local.service_definitions)
  filename = "ansible_roles/files/services/${local.service_definitions[count.index].name}.yaml"
  file_permission = "0440"
  content = local.service_definitions[count.index].content
}

# script to ssh into nat node
resource "local_file" "nat-ssh-script" {
  filename = "ssh-nat.sh"
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-nat-script.tpl",
    {
      nat_public_ip = ionoscloud_server.nat.primary_ip
      ssh_key_private_path = var.cluster_private_key_filename
    }
  )
}

# script to ssh into orchestrator via ssh proxy
resource "local_file" "orchestrator-ssh-script" {
  filename = "ssh-orchestrator.sh"
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-protected-node-script.tpl",
    {
      node_ip = ionoscloud_server.orchestrator.primary_ip
      nat_public_ip = ionoscloud_server.nat.primary_ip
      ssh_key_private_path = var.cluster_private_key_filename
    }
  )
}

# script to ssh into node via ssh proxy
resource "local_file" "node-ssh-script" {
  count = length(local.nodes)
  filename = "ssh-${local.nodes[count.index].name}.sh"
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-protected-node-script.tpl",
    {
      node_ip = ionoscloud_server.node[count.index].primary_ip
      nat_public_ip = ionoscloud_server.nat.primary_ip
      ssh_key_private_path = var.cluster_private_key_filename
    }
  )
}

# stackable client script
resource "local_file" "stackable-client" {
  filename = "resources/stackable.sh"
  content = templatefile("${path.module}/templates/stackable-script.tpl",
    {
      nodes = ionoscloud_server.node
      orchestrator = ionoscloud_server.orchestrator
      nat_public_ip = ionoscloud_server.nat.primary_ip
    }
  )
  file_permission = "0550"
} 

module "wireguard" {
  count                     = can(yamldecode(file("cluster.yaml"))["spec"]["wireguard"]) ? (yamldecode(file("cluster.yaml"))["spec"]["wireguard"] ? 1 : 0) : 1 
  source                    = "../wireguard"
  server_config_filename    = "ansible_roles/files/wireguard_server.conf"
  client_config_base_path   = "resources/wireguard-client-config"
  allowed_ips               = concat([ for node in ionoscloud_server.node: node.primary_ip ], [ionoscloud_server.orchestrator.primary_ip])
  endpoint_ip               = ionoscloud_server.nat.primary_ip
}

