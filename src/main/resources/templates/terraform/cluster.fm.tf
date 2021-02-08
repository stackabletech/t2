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

variable "ionos_datacenter" {
  description = "Username to be used with the Profitbricks Cloud Provider - set using environment variable TF_VAR_ionos_datacenter"
  type        = string
  sensitive   = true
}

provider "profitbricks" {
  username = var.ionos_username
  password = var.ionos_password
}

resource "profitbricks_datacenter" "datacenter" {
  name = var.ionos_datacenter
  location = "de/fra"
  description = "Provisioned via terraform by T2"
}

data "profitbricks_image" "centos7" {
  name     = "CentOS"
  type     = "HDD"
  version  = "7"
  location = "de/fra"
}

# Internet facing lan
resource "profitbricks_lan" "external" {
  name = "External Network"
  datacenter_id = profitbricks_datacenter.datacenter.id
  public = true
}

# NAT Server on the Edge to forward requests and serve as VPN endpoint
resource "profitbricks_server" "nat" {
  name = "nat"
  datacenter_id = profitbricks_datacenter.datacenter.id
  cores = 2
  ram = 1024
  availability_zone = "ZONE_1"

  image_name = data.profitbricks_image.centos7.name
  ssh_key_path = [ "${ssh_key_public}" ]

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

resource "local_file" "ipv4_file" {
    file_permission = "0440"
    content     = profitbricks_server.nat.primary_ip
    filename = "ip4v"
}
