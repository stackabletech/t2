terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "6.1.3"
    }
  }
}

variable "datacenter_name" {
  type = string
}

variable "datacenter_location" {
  type = string
}

variable "datacenter_description" {
  type = string
}

# Datacenter
resource "ionoscloud_datacenter" "datacenter" {
  name = var.datacenter_name
  location = var.datacenter_location
  description = var.datacenter_description
}

# Internet facing LAN
resource "ionoscloud_lan" "external" {
  name = "External Network"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  public = true
}

# Private LAN
resource "ionoscloud_lan" "internal" {
  name = "Internal Network"
  datacenter_id = ionoscloud_datacenter.datacenter.id
  public = false
}

# datacenter
output "datacenter" {
  value = ionoscloud_datacenter.datacenter
}

# internal_lan
output "internal_lan" {
  value = ionoscloud_lan.internal
}

# external_lan
output "external_lan" {
  value = ionoscloud_lan.external
}
