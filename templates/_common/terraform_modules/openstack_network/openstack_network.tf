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

# Security group needed for all the nodes
resource "openstack_networking_secgroup_v2" "secgroup_default" {
  name                    = "${var.cluster_name}-secgroup-default"
  delete_default_rules    = true
}

# Any host which is also in the default group can access the node
resource "openstack_networking_secgroup_rule_v2" "secgroup_default_rule_ingress_ipv4_from_within_okay" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_group_id   = openstack_networking_secgroup_v2.secgroup_default.id
  security_group_id = openstack_networking_secgroup_v2.secgroup_default.id
}

# Every host in the default group can access the outside world
resource "openstack_networking_secgroup_rule_v2" "secgroup_default_rule_egress_ipv4_to_everywhere_okay" {
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_default.id
}

# SSH allowed from everywhere
resource "openstack_networking_secgroup_rule_v2" "secgroup_default_rule_ingress_for_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  port_range_min    = "22"
  port_range_max    = "22"
  security_group_id = openstack_networking_secgroup_v2.secgroup_default.id
}

# Security group for the node offering wireguard service
resource "openstack_networking_secgroup_v2" "secgroup_wireguard" {
  name                    = "${var.cluster_name}-secgroup-wireguard"
  delete_default_rules    = true
}

# UDP open on wireguard-port
resource "openstack_networking_secgroup_rule_v2" "secgroup_wireguard_rule_ingress_for_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  protocol          = "udp"
  port_range_min    = "52888"
  port_range_max    = "52888"
  security_group_id = openstack_networking_secgroup_v2.secgroup_wireguard.id
}

output "cluster_ip" {
  value = openstack_compute_floatingip_v2.cluster_ip.address
  description = "Public IP of the cluster"
}

output "network_name" {
  value = openstack_networking_network_v2.network.name
  description = "Name of the newly created network"
}

output "secgroup_default" {
  value = openstack_networking_secgroup_v2.secgroup_default
}

output "secgroup_wireguard" {
  value = openstack_networking_secgroup_v2.secgroup_wireguard
}

# This resource can be used to express the dependency on network_readiness
output "network_ready_flag" {
  value = openstack_networking_router_interface_v2.router_interface
  description = "Resource on which any subsequently created resources should depend on if they need an up-and-running network"
}
