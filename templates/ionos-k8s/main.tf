terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    ionoscloud = {
      source = "ionos-cloud/ionoscloud"
      version = "6.3.1"
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

variable "cluster_id" {
  description = "UUID of the cluster"
  type        = string
}

locals {
  cluster_name = "t2-${substr(var.cluster_id, 0, 8)}"
  region = yamldecode(file("cluster.yaml"))["spec"]["region"]
  description = "t2-cluster-id: ${var.cluster_id}"
}

provider "ionoscloud" {
  username = var.ionos_username
  password = var.ionos_password
}

resource "ionoscloud_k8s_cluster" "cluster" {
  name        = "${local.cluster_name}-k8s"
  k8s_version = can(yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"]) ? yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"] : null
}

# Datacenter
resource "ionoscloud_datacenter" "datacenter" {
  name                = "${local.cluster_name}-k8s-nodes"
  location            = local.region
  description         = local.description
}


resource "ionoscloud_k8s_node_pool" "node_pool" {
  name              = "${local.cluster_name}-node-pool"
  k8s_version       = ionoscloud_k8s_cluster.cluster.k8s_version
  datacenter_id     = ionoscloud_datacenter.datacenter.id
  k8s_cluster_id    = ionoscloud_k8s_cluster.cluster.id
  cpu_family        = "INTEL_SKYLAKE"
  availability_zone = "AUTO"
  storage_type      = can(yamldecode(file("cluster.yaml"))["spec"]["nodes"]["diskType"]) ? yamldecode(file("cluster.yaml"))["spec"]["nodes"]["diskType"] : "SSD"
  node_count        = can(yamldecode(file("cluster.yaml"))["spec"]["nodes"]["count"]) ? yamldecode(file("cluster.yaml"))["spec"]["nodes"]["count"] : 3
  cores_count       = can(yamldecode(file("cluster.yaml"))["spec"]["nodes"]["numberOfCores"]) ? yamldecode(file("cluster.yaml"))["spec"]["nodes"]["numberOfCores"] : 4
  ram_size          = can(yamldecode(file("cluster.yaml"))["spec"]["nodes"]["memoryMb"]) ? yamldecode(file("cluster.yaml"))["spec"]["nodes"]["memoryMb"] : 4096
  storage_size      = can(yamldecode(file("cluster.yaml"))["spec"]["nodes"]["diskSizeGb"]) ? yamldecode(file("cluster.yaml"))["spec"]["nodes"]["diskSizeGb"] : 250
}

data "ionoscloud_k8s_cluster" "cluster" {
  id = ionoscloud_k8s_cluster.cluster.id
  # We need this dependency because non-admin users in IONOS Cloud are only allowed to download the 
  # kubeconfig (part of this data source) if they own the attached nodepool.
  depends_on = [
    ionoscloud_k8s_node_pool.node_pool  
  ]
}

# write kubeconfig to file
resource "local_file" "kubeconfig" {
  filename = "kubeconfig"
  content = data.ionoscloud_k8s_cluster.cluster.kube_config
  file_permission = "0400"
} 

# create file w/ stackable component versions for Ansible inventory
module "stackable_component_versions" {
  source = "./terraform_modules/stackable_component_versions"
}

# extract service definitions from the cluster definition
module "stackable_service_definitions" {
  source = "./terraform_modules/stackable_service_definitions"
}

# convert the metadata/annotations from the cluster definition to Ansible variables
# and add specific values for the template
module "metadata_annotations" {
  source = "../metadata_annotations"
  cloud_vendor = "IONOS Cloud"
  k8s = "managed Kubernetes"
  node_os = "unknown"
}

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "inventory/inventory"
  content = templatefile("inventory.tpl",
    {
      location = replace(local.region, "/", "_")
      node_pool = ionoscloud_k8s_node_pool.node_pool
      cluster_name = local.cluster_name
      cluster_id = var.cluster_id
    }
  )
  file_permission = "0440"
}
