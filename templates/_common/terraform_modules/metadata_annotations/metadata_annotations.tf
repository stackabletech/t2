# This Terraform script reads the metadata/annotations section from the cluster definition
# and transforms the values to a Ansible variable file.

terraform {
  required_version = ">= 0.15, < 2.0.0"
}

variable "cloud_vendor" {
  type = string
  description = "name of the cloud vendor this cluster runs on"
}

variable "k8s" {
  type = string
  description = "Kubernetes flavor used in this cluster"
}

variable "node_os" {
  type = string
  description = "operating system the Kubernetes nodes run on"
}

locals {
  annotations = concat(can(yamldecode(file("cluster.yaml"))["metadata"]["annotations"]) ? [
    for k,v in yamldecode(file("cluster.yaml"))["metadata"]["annotations"]: {
      key = k
      value = yamldecode(file("cluster.yaml"))["metadata"]["annotations"][k]
    }
    ] : [],
    [ 
      { "key" = "t2.stackable.tech/cloud-vendor", "value" = var.cloud_vendor },
      { "key" = "t2.stackable.tech/k8s", "value" = var.k8s },
      { "key" = "t2.stackable.tech/node-os", "value" = var.node_os }
    ]
  )
}

# variable file for Ansible containing versions of Stackable components
resource "local_file" "metadata-annotations" {
  filename = "inventory/group_vars/all/metadata_annotations.yml"
  content = templatefile("${path.module}/templates/metadata-annotations.tpl",
    {
      annotations = local.annotations
    }
  )
  file_permission = "0440"
}

