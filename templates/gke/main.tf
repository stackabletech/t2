terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.34.0"
    }
  }
}

variable "cluster_name" {
  description = "Name of the cluster, used as a prefix on the names of the resources created here"
  type        = string
}

variable "google_cloud_project_id" {
  description = "Project ID in Google Cloud in which the cluster is to be created"
  type        = string
}

locals {
  # region from cluster definition file
  region = can(yamldecode(file("cluster.yaml"))["spec"]["region"]) ? yamldecode(file("cluster.yaml"))["spec"]["region"] : "europe-central2"
}

provider "google" {
  project = var.google_cloud_project_id
  region  = local.region
}

# Determine zones which can be used for the cluster
data "google_compute_zones" "available" {
}

locals {
  zone = data.google_compute_zones.available.names[0]
}

# VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}"
  auto_create_subnetworks = "false"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}"
  region        = local.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"
}

# GKE cluster
resource "google_container_cluster" "cluster" {
  name     = "${var.cluster_name}"
  location = local.zone
  initial_node_count = can(yamldecode(file("cluster.yaml"))["spec"]["node_count"]) ? yamldecode(file("cluster.yaml"))["spec"]["node_count"] : 3
  min_master_version = can(yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"]) ? yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"] : null
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
  node_config {
    machine_type = can(yamldecode(file("cluster.yaml"))["spec"]["machineType"]) ? yamldecode(file("cluster.yaml"))["spec"]["machineType"] : "e2-standard-2"
  }
  private_cluster_config {
    enable_private_nodes = true
    enable_private_endpoint = false 
    master_ipv4_cidr_block = "10.5.0.0/28"
  }
  ip_allocation_policy {
  }
}

# Create kubeconfig
resource "null_resource" "kubeconfig" {
  provisioner "local-exec" {
    command = "KUBECONFIG=resources/kubeconfig gcloud container clusters get-credentials ${google_container_cluster.cluster.name} --zone ${local.zone} --project ${var.google_cloud_project_id}"
  }
  depends_on = [
    google_container_cluster.cluster
  ]
  provisioner "local-exec" {
    command = "rm resources/kubeconfig"
    when = destroy
  }
}

# create file w/ stackable component versions for Ansible inventory
module "stackable_component_versions" {
  source = "./terraform_modules/stackable_component_versions"
}

# extract service definitions from the cluster definition
module "stackable_service_definitions" {
  source = "./terraform_modules/stackable_service_definitions"
}

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "inventory/inventory"
  content = templatefile("inventory.tpl",
    {
      location = "${google_container_cluster.cluster.location}"
    }
  )
  file_permission = "0440"
}

# Create cluster admin account for this cluster
resource "google_service_account" "cluster_admin" {
  account_id   = "${var.cluster_name}-cluster-admin"
  display_name = "Cluster Admin for ${var.cluster_name}"
  provisioner "local-exec" {
    command = "gcloud --project ${var.google_cloud_project_id} iam service-accounts keys create resources/credentials.json --iam-account=${google_service_account.cluster_admin.email}"
  }
  provisioner "local-exec" {
    command = "rm resources/credentials.json"
    when = destroy
  }
}

resource "google_project_iam_member" "project" {
  project = var.google_cloud_project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.cluster_admin.email}"
}
