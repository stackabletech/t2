terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.28.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "2.2.3"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.13.1"
    }
  }

  required_version = ">= 0.15, < 2.0.0"
}

variable "aws_access_key" { 
  description = "AWS access key"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" { 
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

locals {
  region = can(yamldecode(file("cluster.yaml"))["spec"]["region"]) ? yamldecode(file("cluster.yaml"))["spec"]["region"] : "eu-central-1"
}

provider "aws" {
  region = local.region
  access_key  = var.aws_access_key
  secret_key  = var.aws_secret_access_key
}

resource "aws_iam_user" "cluster_admin" {
  name = "${var.cluster_name}-cluster-admin"
}

data "template_file" "cluster_admin_user_policy" {
  template = "${file("cluster_admin_user_policy.tpl")}"
  vars = {
    cluster_arn = data.aws_eks_cluster.cluster.arn 
  }
}

resource "aws_iam_user_policy" "cluster_admin_policy" {
  name = "${var.cluster_name}-cluster-admin-policy"
  user = aws_iam_user.cluster_admin.name

  policy = data.template_file.cluster_admin_user_policy.rendered
}

resource "aws_iam_access_key" "cluster_admin" {
  user = aws_iam_user.cluster_admin.name
}

resource "local_file" "credentials" {
  filename = "resources/credentials.yaml"
  content = templatefile("credentials.tpl",
    {
      arn = aws_iam_user.cluster_admin.arn
      unique_id = aws_iam_user.cluster_admin.unique_id
      aws_key = aws_iam_access_key.cluster_admin.id
      aws_secret_key = aws_iam_access_key.cluster_admin.secret
    }
  )
  file_permission = "0440"
} 

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.2.0"

  name                 = "${var.cluster_name}-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_security_group" "worker_group" {
  name_prefix = "worker_group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "17.24.0"
  cluster_name    = var.cluster_name
  cluster_version = can(yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"]) ? yamldecode(file("cluster.yaml"))["spec"]["k8sVersion"] : "1.21"
  subnets         = module.vpc.private_subnets

  vpc_id = module.vpc.vpc_id

  workers_group_defaults = {
    root_volume_type = "gp2"
  }

  worker_groups = [
    {
      name                          = "${var.cluster_name}-worker-group"
      instance_type                 = can(yamldecode(file("cluster.yaml"))["spec"]["awsInstanceType"]) ? yamldecode(file("cluster.yaml"))["spec"]["awsInstanceType"] : "t2.small"
      additional_security_group_ids = [aws_security_group.worker_group.id]
      asg_min_size                  = 1
      asg_max_size                  = can(yamldecode(file("cluster.yaml"))["spec"]["node_count"]) ? yamldecode(file("cluster.yaml"))["spec"]["node_count"] : 3
      asg_desired_capacity          = can(yamldecode(file("cluster.yaml"))["spec"]["node_count"]) ? yamldecode(file("cluster.yaml"))["spec"]["node_count"] : 3
    }
  ]
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  token                  = data.aws_eks_cluster_auth.cluster.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
}

resource "null_resource" "kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${local.region} --kubeconfig kubeconfig"
  }
  depends_on = [
    data.aws_eks_cluster.cluster
  ]
}

resource "null_resource" "patch_aws_auth" {
  provisioner "local-exec" {
    command = <<EOT
      sleep 60 && kubectl --kubeconfig kubeconfig patch configmap -n kube-system aws-auth -p '{"data":{"mapUsers":"[{\"userarn\": \"${aws_iam_user.cluster_admin.arn}\", \"username\": \"${var.cluster_name}-cluster-admin\", \"groups\": [\"system:masters\"]}]"}}'
    EOT
  }
  depends_on = [
    null_resource.kubeconfig
  ]
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
      location = local.region
    }
  )
  file_permission = "0440"
}
