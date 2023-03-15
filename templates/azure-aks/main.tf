terraform {
  required_version = ">= 0.15, < 2.0.0"
}

# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.46.0"
    }
  }
}

variable "az_subscription_id" { 
    description = "Microsoft Azure Subscription ID"
    type        = string
    sensitive   = true
}

variable "az_subscription_tenant_id" { 
    description = "Microsoft Azure Subscription Tenant ID"
    type        = string
    sensitive   = true
}

variable "az_service_principal_app_id" { 
    description = "Microsoft Azure Service Principal App ID"
    type        = string
    sensitive   = true
}

variable "az_service_principal_password" { 
    description = "Microsoft Azure Service Principal Password"
    type        = string
    sensitive   = true
}

variable "cluster_id" {
  description = "UUID of the cluster"
  type        = string
}

locals {
  cluster_name = "t2-${substr(var.cluster_id, 0, 8)}"
  tags = {
    t2-cluster-id = var.cluster_id
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
    features {}
  
    subscription_id   = var.az_subscription_id
    tenant_id         = var.az_subscription_tenant_id
    client_id         = var.az_service_principal_app_id
    client_secret     = var.az_service_principal_password
}


resource "azurerm_resource_group" "resource-group" {
  name     = "${local.cluster_name}-resource-group"
  location = can(yamldecode(file("cluster.yaml"))["spec"]["location"]) ? yamldecode(file("cluster.yaml"))["spec"]["location"] : "West Europe"
}

resource "azurerm_kubernetes_cluster" "kubernetes_cluster" {
  name                = "${local.cluster_name}-kubernetes-cluster"
  location            = azurerm_resource_group.resource-group.location
  resource_group_name = azurerm_resource_group.resource-group.name
  dns_prefix          = "${local.cluster_name}"
  kubernetes_version  = can(yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"]) ? yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"] : null

  default_node_pool {
    name       = "default"
    node_count = can(yamldecode(file("cluster.yaml"))["spec"]["nodes"]["count"]) ? yamldecode(file("cluster.yaml"))["spec"]["nodes"]["count"] : 3
    vm_size    = can(yamldecode(file("cluster.yaml"))["spec"]["nodes"]["vmSize"]) ? yamldecode(file("cluster.yaml"))["spec"]["nodes"]["vmSize"] : "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# write kubeconfig to file
resource "local_file" "kubeconfig" {
  filename = "kubeconfig"
  content = azurerm_kubernetes_cluster.kubernetes_cluster.kube_config_raw
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
  source = "./terraform_modules/metadata_annotations"
  cloud_vendor = "Microsoft Azure"
  k8s = "AKS"
  node_os = "unknown"
}

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "inventory/inventory"
  content = templatefile("inventory.tpl",
    {
      location = azurerm_kubernetes_cluster.kubernetes_cluster.location
      node_size = azurerm_kubernetes_cluster.kubernetes_cluster.default_node_pool[0].vm_size
      cluster_name = local.cluster_name
      cluster_id = var.cluster_id
    }
  )
  file_permission = "0440"
}
