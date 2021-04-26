terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "5.0.4"
    }
  }
}

resource "tls_private_key" "cluster_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "cluster_private_key" { 
  filename = "${path.module}/cluster_key"
  content = tls_private_key.cluster_key.private_key_pem
  file_permission = "0400"
}

resource "local_file" "cluster_public_key" { 
  filename = "${path.module}/cluster_key.pub"
  content = tls_private_key.cluster_key.public_key_openssh
  file_permission = "0440"
}

variable "ionos_username" {
  description = "Username to be used with the IONOS Cloud Provider - set using environment variable TF_VAR_ionos_username"
  type        = string
  sensitive   = true
}

variable "ionos_password" {
  description = "Password to be used with the IONOS Cloud Provider - set using environment variable TF_VAR_ionos_password"
  type        = string
  sensitive   = true
}

variable "ionos_datacenter" {
  description = "Name of the datacenter in the IONOS cloud - set using environment variable TF_VAR_ionos_datacenter"
  type        = string
}

provider "ionoscloud" {
  username = var.ionos_username
  password = var.ionos_password
}

variable "ssh_client_keys" {
  default = [ 
    [#list clusterDefinition.publicKeys as ssh_key]"[= ssh_key ]"[#sep],
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


resource "ionoscloud_datacenter" "datacenter" {
  name = var.ionos_datacenter
  location = "[= clusterDefinition.spec.region ]"
  description = "[= clusterDefinition.metadata.description ]"
}

data "ionoscloud_image" "os_image" {
  name     = "Debian"
  type     = "HDD"
  version  = "10"
  location = "[= clusterDefinition.spec.region ]"
}

# Internet facing lan
resource "ionoscloud_lan" "external" {
  name = "External Network"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  public = true
}

// Private lan
resource "ionoscloud_lan" "internal" {
  name = "Internal Network"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  public = false
}

# NAT Server on the Edge to forward requests and serve as VPN endpoint
resource "ionoscloud_server" "nat" {
  name = "nat"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  cores = 2
  ram = 1024
[#if clusterDefinition.spec.cpuFamily??]
  cpu_family = "[= clusterDefinition.spec.cpuFamily]"
[/#if]
  availability_zone = "ZONE_1"

  image_name = data.ionoscloud_image.os_image.name
  ssh_key_path = [ local_file.cluster_public_key.filename ]

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
  cores = 4
  ram = 8192
[#if clusterDefinition.spec.cpuFamily??]
  cpu_family = "[= clusterDefinition.spec.cpuFamily]"
[/#if]
  availability_zone = "ZONE_1"

  image_name = data.ionoscloud_image.os_image.name
  ssh_key_path = [ local_file.cluster_public_key.filename ]

  volume {
    name = "orchestrator-storage"
    size = 15
    disk_type = "HDD"
  }

  nic {
    name = "orchestrator-internal-nic"
    lan = ionoscloud_lan.internal.id
    dhcp = true
    firewall_active = false
  }
}

[#list clusterDefinition.spec.nodes as node_type, node_spec]
resource "ionoscloud_server" "[= node_type ]" {
  count = [= node_spec.numberOfNodes ]
  name = "[= node_type ]-${count.index + 1}"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  cores = [= node_spec.numberOfCores ]
  ram = [= node_spec.memoryMb ]
[#if clusterDefinition.spec.cpuFamily??]
  cpu_family = "[= clusterDefinition.spec.cpuFamily]"
[/#if]
  availability_zone = "ZONE_1"

  image_name = data.ionoscloud_image.os_image.name
  ssh_key_path = [ local_file.cluster_public_key.filename ]

  volume {
    name = "[= node_type ]-${count.index + 1}-storage"
    size = [= node_spec.diskSizeGb ]
    disk_type = "[= node_spec.diskType ]"
  }

  nic {
    name = "[= node_type ]-${count.index + 1}-internal-nic"
    lan = ionoscloud_lan.internal.id
    dhcp = true
    firewall_active = false
  }
}

[/#list]

# Generate file containing IP of bastion host.
# This is used by T2 to create DNS record
resource "local_file" "ipv4_file" {
    filename = "ipv4"
    content = ionoscloud_server.nat.primary_ip
    file_permission = "0440"
}

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "${path.module}/inventory/inventory"
  content = templatefile("${path.module}/templates/ansible-inventory.tpl",
    {
      nodetypes = [ [#list clusterDefinition.spec.nodes as node_type, node_spec]"[= node_type ]"[#sep] , [/#list] ]
      nodes = { [#list clusterDefinition.spec.nodes as node_type, node_spec]"[= node_type ]" : ionoscloud_server.[= node_type ][#sep] , [/#list] }
      nat = ionoscloud_server.nat
      nat_public_ip = ionoscloud_server.nat.primary_ip
      nat_internal_ip = ionoscloud_nic.nat_internal.ips[0]
      orchestrator = ionoscloud_server.orchestrator
      ssh_key_private_path = local_file.cluster_private_key.filename
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

# service definition files
[#if clusterDefinition.services??]
[#list clusterDefinition.services as service_name, service_definition]
resource "local_file" "service-[= service_name]" {
  filename = "roles/services/files/[= service_name].yaml"
  file_permission = "0440"
  content = <<-END_OF_SERVICE_DEF
[= service_definition]
END_OF_SERVICE_DEF
}

[/#list]
[/#if]

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
      nodes = [ [#list clusterDefinition.spec.nodes as node_type, node_spec]ionoscloud_server.[= node_type ][#sep] , [/#list] ]
      orchestrator_ip = ionoscloud_server.orchestrator.primary_ip
      wg_client_private_key = var.wireguard_client_private_keys[count.index]
      index = count.index
      wg_nat_public_key = var.wireguard_nat_public_key
      nat_public_ip = ionoscloud_server.nat.primary_ip
    }
  )
}


# script to ssh into nat node
resource "local_file" "nat-ssh-script" {
  filename = "ssh-nat.sh"
  file_permission = "0550"
  content = templatefile("${path.module}/templates/ssh-nat-script.tpl",
    {
      nat_public_ip = ionoscloud_server.nat.primary_ip
      ssh_key_private_path = local_file.cluster_private_key.filename
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
      node_ip = ionoscloud_server.[=node_type][count.index].primary_ip
      nat_public_ip = ionoscloud_server.nat.primary_ip
      ssh_key_private_path = local_file.cluster_private_key.filename
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
      node_ip = ionoscloud_server.orchestrator.primary_ip
      nat_public_ip = ionoscloud_server.nat.primary_ip
      ssh_key_private_path = local_file.cluster_private_key.filename
    }
  )
}

# stackable client script
resource "local_file" "stackable-client" {
  filename = "${path.module}/resources/stackable.sh"
  content = templatefile("${path.module}/templates/stackable-script.tpl",
    {
      nodetypes = [ [#list clusterDefinition.spec.nodes as node_type, node_spec]"[= node_type ]"[#sep] , [/#list] ]
      nodes = { [#list clusterDefinition.spec.nodes as node_type, node_spec]"[= node_type ]" : ionoscloud_server.[= node_type ][#sep] , [/#list] }
      orchestrator = ionoscloud_server.orchestrator
      nat_public_ip = ionoscloud_server.nat.primary_ip
    }
  )
  file_permission = "0550"
} 
