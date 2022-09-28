# Creates an HCloud network/subnet for a cluster to be built.

terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      version = "1.35.2"
    }
  }
}

variable "cluster_name" {
  type = string
  description = "name of the cluster"
}

resource "hcloud_network" "network" {
  name     = "${var.cluster_name}-network"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "subnet" {
  type         = "cloud"
  network_id   = hcloud_network.network.id
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

output "network" {
  value = hcloud_network.network
}

output "subnet" {
  value = hcloud_network_subnet.subnet
}