terraform {
  required_providers {
    profitbricks = {
      source = "ionos-cloud/profitbricks"
      version = "1.6.5"
    }
  }
}

variable "ionos_username" {
  description = "Username to be used with the Profitbricks Cloud Provider - set using environment variable TF_VAR_ionos_username"
  type        = string
  sensitive   = true
}

variable "ionos_password" {
  description = "Password to be used with the Profitbricks Cloud Provider - set using environment variable TF_VAR_ionos_password"
  type        = string
  sensitive   = true
}

provider "profitbricks" {
  username = var.ionos_username
  password = var.ionos_password
}

resource "profitbricks_datacenter" "datacenter" {
  name = "[= datacenter_name ]"
  location = "[= spec.region ]"
  description = "[= metadata.description ]"
}

data "profitbricks_image" "centos7" {
  name     = "[= spec.osName ]"
  type     = "HDD"
  version  = "[= spec.osVersion ]"
  location = "[= spec.region ]"
}

# Internet facing lan
resource "profitbricks_lan" "external" {
  name = "External Network"
  datacenter_id = profitbricks_datacenter.datacenter.id
  public = true
}

// Private lan
resource "profitbricks_lan" "internal" {
  name = "Internal Network"
  datacenter_id = profitbricks_datacenter.datacenter.id
  public = false
}

# NAT Server on the Edge to forward requests and serve as VPN endpoint
resource "profitbricks_server" "nat" {
  name = "nat"
  datacenter_id = profitbricks_datacenter.datacenter.id
  cores = 2
  ram = 1024
  availability_zone = "ZONE_1"

  image_name = data.profitbricks_image.centos7.name
  ssh_key_path = [ "[=ssh_key_public_path]" ]

  volume {
    name = "nat-storage"

    size = 15
    disk_type = "SSD"
  }

  nic {
    lan = profitbricks_lan.external.id
    dhcp = true
    firewall_active = false
  }
}

resource "profitbricks_nic" "nat_internal" {
  datacenter_id = profitbricks_datacenter.datacenter.id
  lan = profitbricks_lan.internal.id
  server_id = profitbricks_server.nat.id

  dhcp = true
  firewall_active = false
}

[#list spec.nodes as node_type, node_spec]
resource "profitbricks_server" "[= node_type ]" {
  count = [= node_spec.numberOfNodes ]
  name = "[= node_type ]-${count.index + 1}"
  datacenter_id = profitbricks_datacenter.datacenter.id
  cores = [= node_spec.numberOfCores ]
  ram = [= node_spec.memoryMb ]
  availability_zone = "ZONE_1"

  image_name = data.profitbricks_image.centos7.name
  ssh_key_path = [ "[=ssh_key_public_path]" ]

  volume {
    name = "[= node_type ]-storage-${count.index + 1}"
    size = [= node_spec.diskSizeGb ]
    disk_type = "[= node_spec.diskType ]"
  }

  nic {
    name = "internal-nic-[= node_type ]-${count.index + 1}"
    lan = profitbricks_lan.internal.id
    dhcp = true
    firewall_active = false
  }
}

[/#list]

# Generate file containing IP of bastion host.
# This is used by T2 to create DNS record
resource "local_file" "ipv4_file" {
    filename = "ipv4"
    content = profitbricks_server.nat.primary_ip
    file_permission = "0440"
}

# generate inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "${path.module}/inventory"
  content = templatefile("${path.module}/templates/ansible-inventory.tpl",
    {
      nodetypes = [ [#list spec.nodes as node_type, node_spec]"[= node_type ]"[#sep] , [/#list] ]
      nodes = { [#list spec.nodes as node_type, node_spec]"[= node_type ]" : profitbricks_server.[= node_type ][#sep] , [/#list] }
      nat = profitbricks_server.nat
      nat_public_hostname = "[= public_hostname ]"
      nat_internal_ip = profitbricks_nic.nat_internal.ips[0]
      ssh_key_private_path = "[= ssh_key_private_path ]"
    }
  )
  file_permission = "0440"
} 