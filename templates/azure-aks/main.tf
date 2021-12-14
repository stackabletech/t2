terraform {
  required_version = ">= 0.15, < 2.0.0"
}

# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
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

variable "cluster_name" {
  description = "Name of the cluster, used as a prefix on the names of the resources created here"
  type        = string
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
  name     = "${var.cluster_name}-resource-group"
  location = "West Europe"
}

resource "azurerm_kubernetes_cluster" "kubernetes-cluster" {
  name                = "${var.cluster_name}-kubernetes-cluster"
  location            = azurerm_resource_group.resource-group.location
  resource_group_name = azurerm_resource_group.resource-group.name
  dns_prefix          = "${var.cluster_name}"

  default_node_pool {
    name       = "default"
    node_count = 5
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

# extract client certificate to file
resource "local_file" "client-certificate" {
  filename = "resources/client_certificate"
  content = azurerm_kubernetes_cluster.kubernetes-cluster.kube_config.0.client_certificate
  file_permission = "0400"
} 

# extract kubeconfig to file
resource "local_file" "kubeconfig" {
  filename = "resources/kubeconfig"
  content = azurerm_kubernetes_cluster.kubernetes-cluster.kube_config_raw
  file_permission = "0400"
} 

module "stackable_component_versions" {
  source = "./terraform_modules/stackable_component_versions"
}
