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

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

provider "ionoscloud" {
  username = var.ionos_username
  password = var.ionos_password
}

resource "ionoscloud_k8s_cluster" "cluster" {
  name        = "${var.cluster_name}-k8s"
  k8s_version = can(yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"]) ? yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"] : null
}

# Datacenter
resource "ionoscloud_datacenter" "datacenter" {
  name = "${var.cluster_name}-k8s-nodes"
  location = yamldecode(file("cluster.yaml"))["spec"]["region"]
  description = "Datacenter containing nodes for cluster ${var.cluster_name}-k8s"
}


resource "ionoscloud_k8s_node_pool" "node_pool" {
  name        = "${var.cluster_name}-node-pool"
  k8s_version = can(yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"]) ? yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"] : null
  datacenter_id     = ionoscloud_datacenter.datacenter.id
  k8s_cluster_id    = ionoscloud_k8s_cluster.cluster.id
  cpu_family        = "INTEL_SKYLAKE"
  availability_zone = "AUTO"
  storage_type      = "SSD"
  node_count        = can(yamldecode(file("cluster.yaml"))["spec"]["node_count"]) ? yamldecode(file("cluster.yaml"))["spec"]["node_count"] : 3
  cores_count       = 2
  ram_size          = 2048
  storage_size      = 40
}

data "ionoscloud_k8s_cluster" "cluster" {
  name = "${var.cluster_name}-k8s"
}

# write kubeconfig to file
resource "local_file" "kubeconfig" {
  filename = "resources/kubeconfig"
  content = data.ionoscloud_k8s_cluster.cluster.kube_config
  file_permission = "0400"
} 

# create file w/ stackable component versions for Ansible inventory
module "stackable_component_versions" {
  source = "./terraform_modules/stackable_component_versions"
}



