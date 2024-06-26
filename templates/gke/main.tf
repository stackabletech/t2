terraform {
  required_version = ">= 0.15, < 2.0.0"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.34.0"
    }
  }
}

variable "cluster_id" {
  description = "UUID of the cluster"
  type        = string
}

variable "google_cloud_project_id" {
  description = "Project ID in Google Cloud in which the cluster is to be created"
  type        = string
}

locals {
  cluster_name = "t2-${substr(var.cluster_id, 0, 8)}"
  region = can(yamldecode(file("cluster.yaml"))["spec"]["region"]) ? yamldecode(file("cluster.yaml"))["spec"]["region"] : "europe-central2"
  labels = {
    t2-cluster-id = var.cluster_id
  }
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
  name                    = "${local.cluster_name}"
  auto_create_subnetworks = "false"
}

# Allow all for external access in tests
resource "google_compute_firewall" "rules" {
  name                    = "${local.cluster_name}"
  network                 = "${local.cluster_name}"
  priority                = 0
  source_ranges           = ["0.0.0.0/0"]
  depends_on              = [ google_compute_network.vpc ]

  allow {
    protocol  = "all"
  }
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${local.cluster_name}"
  region        = local.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"
}

# GKE cluster
resource "google_container_cluster" "cluster" {
  name     = "${local.cluster_name}"
  location = local.zone
  initial_node_count = can(yamldecode(file("cluster.yaml"))["spec"]["nodes"]["count"]) ? yamldecode(file("cluster.yaml"))["spec"]["nodes"]["count"] : 3
  min_master_version = can(yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"]) ? yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"] : null
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
  deletion_protection = "false"
  node_config {
    machine_type = can(yamldecode(file("cluster.yaml"))["spec"]["nodes"]["machineType"]) ? yamldecode(file("cluster.yaml"))["spec"]["nodes"]["machineType"] : "e2-standard-2"
  }
  release_channel {
    channel = "RAPID"
  }
  resource_labels = local.labels
}

# Create kubeconfig
resource "null_resource" "kubeconfig" {
  provisioner "local-exec" {
    command = "KUBECONFIG=kubeconfig gcloud container clusters get-credentials ${google_container_cluster.cluster.name} --zone ${local.zone} --project ${var.google_cloud_project_id}"
  }
  depends_on = [
    google_container_cluster.cluster
  ]
  provisioner "local-exec" {
    command = "rm kubeconfig"
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

# convert the metadata/annotations from the cluster definition to Ansible variables
# and add specific values for the template
module "metadata_annotations" {
  source = "./terraform_modules/metadata_annotations"
  cloud_vendor = "Google Cloud"
  k8s = "GKE"
  node_os = "unknown"
}

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "inventory/inventory"
  content = templatefile("inventory.tpl",
    {
      location = google_container_cluster.cluster.location
      node_size = google_container_cluster.cluster.node_config[0].machine_type
      cluster_name = local.cluster_name
      cluster_id = var.cluster_id
    }
  )
  file_permission = "0440"
}

# Create cluster admin account for this cluster
resource "google_service_account" "cluster_admin" {
  account_id   = "${local.cluster_name}-cluster-admin"
  display_name = "Cluster Admin for ${local.cluster_name}"
  provisioner "local-exec" {
    command = "gcloud --project ${var.google_cloud_project_id} iam service-accounts keys create gcloud_credentials.json --iam-account=${google_service_account.cluster_admin.email}"
  }
  provisioner "local-exec" {
    command = "rm gcloud_credentials.json"
    when = destroy
  }
}

data "local_file" "gcloud_credentials" {
    filename = "gcloud_credentials.json"
    depends_on = [ google_service_account.cluster_admin ]
}

resource "google_project_iam_member" "project" {
  project = var.google_cloud_project_id
  role    = "projects/t2-system-under-test/roles/t2.cluster.admin"
  member  = "serviceAccount:${google_service_account.cluster_admin.email}"
}

# File which contains the GKE coordinates needed to access the cluster
resource "local_file" "gke_coordinates" {
  filename = "gke_coordinates.yaml"
  content = yamlencode({ 
    project: var.google_cloud_project_id
    zone: local.zone
    cluster_name: local.cluster_name
  })
}