terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "6.3.5"
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
  name            = var.datacenter_name
  location        = var.datacenter_location
  description     = var.datacenter_description
}

# Internet facing LAN
resource "ionoscloud_lan" "external" {
  name              = "External Network"
  datacenter_id     = ionoscloud_datacenter.datacenter.id
  public            = true
}

# Private LAN
resource "ionoscloud_lan" "internal" {
  name                = "Internal Network"
  datacenter_id       = ionoscloud_datacenter.datacenter.id
  public              = false
}

# IP for NAT gateway
resource "ionoscloud_ipblock" "ips" {
  location        = var.datacenter_location
  size            = 1
  name            = var.datacenter_name
}

# NAT gateway
resource "ionoscloud_natgateway" "natgateway" {
    datacenter_id           = ionoscloud_datacenter.datacenter.id
    name                    = "${var.datacenter_name}-natgateway"
    public_ips              = [ ionoscloud_ipblock.ips.ips[0] ]
     lans {
        id                  = ionoscloud_lan.internal.id
     }
}

# NAT gateway rule
resource "ionoscloud_natgateway_rule" "natgateway_rule" {
    datacenter_id           = ionoscloud_datacenter.datacenter.id
    natgateway_id           = ionoscloud_natgateway.natgateway.id
    name                    = "${var.datacenter_name}-natgateway-rule"
    source_subnet           = replace(ionoscloud_natgateway.natgateway.lans[0].gateway_ips[0], "/\\.\\d+//", ".0/")
    public_ip               = ionoscloud_ipblock.ips.ips[0]
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

# IP of the NAT gateway
output "gateway_ip" {
  value = regex("\\d+\\.\\d+\\.\\d+\\.\\d+", ionoscloud_natgateway.natgateway.lans[0].gateway_ips[0])
}
