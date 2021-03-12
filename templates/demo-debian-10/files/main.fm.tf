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

variable "ssh_client_keys" {
  default = [ 
    [#list clusterDefinition.sshKeys as ssh_key]"[= ssh_key ]"[#sep],
    [/#list] 

  ]
}

variable "wireguard_client_public_keys" {
  default = [ 
    [#list wireguard_client_public_keys as wg_key]"[= wg_key ]"[#sep],
    [/#list] 

  ]
}

variable "wireguard_client_private_keys" {
  default = [ 
    [#list wireguard_client_private_keys as wg_key]"[= wg_key ]"[#sep],
    [/#list] 

  ]
}

variable "wireguard_nat_public_key" {
  default = "[= wireguard_nat_public_key ]"
}

variable "wireguard_nat_private_key" {
  default = "[= wireguard_nat_private_key ]"
}


resource "profitbricks_datacenter" "datacenter" {
  name = "[= datacenter_name ]"
  location = "[= clusterDefinition.spec.region ]"
  description = "[= clusterDefinition.metadata.description ]"
}

data "profitbricks_image" "os_image" {
  name     = "Debian"
  type     = "HDD"
  version  = "10"
  location = "[= clusterDefinition.spec.region ]"
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

  image_name = data.profitbricks_image.os_image.name
  ssh_key_path = [ "[=t2_ssh_key_public]" ]

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

resource "profitbricks_server" "orchestrator" {
  name = "orchestrator"
  datacenter_id = profitbricks_datacenter.datacenter.id
  cores = 2
  ram = 1024
  availability_zone = "ZONE_1"

  image_name = data.profitbricks_image.os_image.name
  ssh_key_path = [ "[=t2_ssh_key_public]" ]

  volume {
    name = "orchestrator-storage"
    size = 15
    disk_type = "HDD"
  }

  nic {
    name = "internal-nic-orchestrator"
    lan = profitbricks_lan.internal.id
    dhcp = true
    firewall_active = false
  }
}

[#list clusterDefinition.spec.nodes as node_type, node_spec]
resource "profitbricks_server" "[= node_type ]" {
  count = [= node_spec.numberOfNodes ]
  name = "[= node_type ]-${count.index + 1}"
  datacenter_id = profitbricks_datacenter.datacenter.id
  cores = [= node_spec.numberOfCores ]
  ram = [= node_spec.memoryMb ]
  availability_zone = "ZONE_1"

  image_name = data.profitbricks_image.os_image.name
  ssh_key_path = [ "[=t2_ssh_key_public]" ]

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

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "${path.module}/inventory/inventory"
  content = templatefile("${path.module}/templates/ansible-inventory.tpl",
    {
      nodetypes = [ [#list clusterDefinition.spec.nodes as node_type, node_spec]"[= node_type ]"[#sep] , [/#list] ]
      nodes = { [#list clusterDefinition.spec.nodes as node_type, node_spec]"[= node_type ]" : profitbricks_server.[= node_type ][#sep] , [/#list] }
      nat = profitbricks_server.nat
      nat_public_hostname = "[= public_hostname ]"
      nat_internal_ip = profitbricks_nic.nat_internal.ips[0]
      orchestrator = profitbricks_server.orchestrator
      ssh_key_private_path = "[= t2_ssh_key_private ]"
      domain = "[= clusterDefinition.domain ]"
    }
  )
  file_permission = "0440"
} 

# variable file for Ansible
resource "local_file" "ansible-variables" {
  filename = "${path.module}/inventory/group_vars/all/all.yml"
  content = templatefile("${path.module}/templates/ansible-variables.tpl",
    {
      ssh_client_keys = var.ssh_client_keys
    }
  )
  file_permission = "0440"
} 

# wireguard configfile for bastion host ('nat')
resource "local_file" "wireguard_nat_config" {
  filename = "${path.module}/roles/nat/files/wg.conf"
  file_permission = "0440"
  content = templatefile("${path.module}/templates/wg.conf.tpl",
    {
      wg_nat_private_key = var.wireguard_nat_private_key
      wg_client_public_keys = var.wireguard_client_public_keys
    }
  )
}

# wireguard configfile for clients
resource "local_file" "wireguard_client_config" {
  count = [= wireguard_client_private_keys?size]
  filename = "${path.module}/resources/wireguard-client-config/${count.index + 1}/wg.conf"
  file_permission = "0440"
  content = templatefile("${path.module}/templates/wg-client.conf.tpl",
    {
      nodes = [ [#list clusterDefinition.spec.nodes as node_type, node_spec]profitbricks_server.[= node_type ][#sep] , [/#list] ]
      orchestrator_ip = profitbricks_server.orchestrator.primary_ip
      wg_client_private_key = var.wireguard_client_private_keys[count.index]
      index = count.index
      wg_nat_public_key = var.wireguard_nat_public_key
      nat_public_hostname = "[= public_hostname ]"
    }
  )
}


# script to ssh into nat node
resource "local_file" "nat-ssh-script" {
  filename = "ssh-nat.sh"
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-nat-script.tpl",
    {
      nat_public_hostname = "[= public_hostname ]"
      ssh_key_private_path = "[= t2_ssh_key_private ]"
    }
  )
}

[#list clusterDefinition.spec.nodes as node_type, node_spec]
# script to ssh into protected [=node_type] nodes via ssh proxy
resource "local_file" "[= node_type ]-ssh-script" {
  count = [= node_spec.numberOfNodes ]
  filename = "ssh-[= node_type ]-${count.index + 1}.sh"
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-script.tpl",
    {
      node_ip = profitbricks_server.[=node_type][count.index].primary_ip
      nat_public_hostname = "[= public_hostname ]"
      ssh_key_private_path = "[= t2_ssh_key_private ]"
    }
  )
}

[/#list]

# script to ssh into orchestrator via ssh proxy
resource "local_file" "orchestrator-ssh-script" {
  filename = "ssh-orchestrator.sh"
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-script.tpl",
    {
      node_ip = profitbricks_server.orchestrator.primary_ip
      nat_public_hostname = "[= public_hostname ]"
      ssh_key_private_path = "[= t2_ssh_key_private ]"
    }
  )
}

