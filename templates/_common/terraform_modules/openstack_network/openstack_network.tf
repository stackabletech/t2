# Creates an OpenStack subnet for a cluster to be built.

terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "1.43.0"
    }
  }
}

variable "cluster_name" {
  type = string
  description = "name of the cluster"
}

variable "external_network_id" {
  type = string
  description = "ID of the network which is connected to the internet"
}

variable "ip_pool" {
  type = string
  description = "name of the IP pool to get the floating IP from"
}

# Create the network
resource "openstack_networking_network_v2" "network" {
  name           = "${var.cluster_name}-network"
  admin_state_up = "true"
}

# Create the subnet
resource "openstack_networking_subnet_v2" "subnet" {
  name       = "${var.cluster_name}-subnet"
  network_id = openstack_networking_network_v2.network.id
  cidr       = "192.168.13.0/24"
  ip_version = 4
}

# Create the router to the external network (aka internet)
resource "openstack_networking_router_v2" "router" {
  name                = "${var.cluster_name}-router"
  admin_state_up      = true
  external_network_id = var.external_network_id
}

# Connect the router to the subnet
resource "openstack_networking_router_interface_v2" "router_interface" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.subnet.id
}

# Obtain a floating IP as a public IP of the cluster (bastion host)
resource "openstack_compute_floatingip_v2" "cluster_ip" {
  pool = var.ip_pool
}

# Unfortunately, we have to fight with some race conditions, so we
# use this timer as a marker to indicate that the network is (= should be) up and running
# This timer resource is exported as an output so that resources in other modules
# (usually compute instances) can depend on it
resource "time_sleep" "network_readiness_delay" {
  depends_on = [ openstack_networking_router_interface_v2.router_interface ]
  create_duration = "5s"
}

output "cluster_ip" {
  value = openstack_compute_floatingip_v2.cluster_ip.address
  description = "Public IP of the cluster"
}

output "network_name" {
  value = openstack_networking_network_v2.network.name
  description = "Name of the newly created network"
}

# This resource can be used to express the dependency on network_readiness
output "network_ready_flag" {
  value = time_sleep.network_readiness_delay
  description = "Timer resource on which any subsequently created resources should depend on if they need an up-and-running network"
}
