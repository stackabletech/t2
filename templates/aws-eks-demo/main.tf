# This template is the result of an AWS EKS spike/PoC
# It is not a fully-fledged T2 template as the user has no means to manipulate the outcome
# (# of nodes, versions, node performance, disk sizes...)
# We decided in/during https://github.com/stackabletech/t2/issues/117 that we leave it like this for now.
# This template proves that an AWS EKS cluster can be used for Stackable.

# AWS credentials with which the cluster is created
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

# This variable is not provided by the T2 automatic cluster provisioning.
# This means that this template can only be used in DIY mode, which is on purpose
# because this template is only for internal purposes as of now.
variable "aws_eks_cluster_name" {
  description = "Name of the AWS EKS cluster"
  type        = string
}

provider "aws" {
  region = "eu-central-1"
  access_key  = var.aws_access_key
  secret_key  = var.aws_secret_access_key
}

# The EKS part of this template was mostly taken from the examples of
# https://github.com/terraform-aws-modules/terraform-aws-eks

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

data "aws_availability_zones" "available" {
}

resource "aws_security_group" "worker_group_mgmt_one" {
  name_prefix = "worker_group_mgmt_one"
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

resource "aws_security_group" "worker_group_mgmt_two" {
  name_prefix = "worker_group_mgmt_two"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "192.168.0.0/16",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.47"

  name                 = "${var.aws_eks_cluster_name}-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.aws_eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.aws_eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "17.1.0"
  cluster_name    = var.aws_eks_cluster_name
  cluster_version = "1.20"
  subnets         = module.vpc.private_subnets

#  tags = {
#    Environment = "test"
#    GithubRepo  = "terraform-aws-eks"
#    GithubOrg   = "terraform-aws-modules"
#  }

  vpc_id = module.vpc.vpc_id

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t3.small"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 2
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },
    {
      name                          = "worker-group-2"
      instance_type                 = "t3.medium"
      additional_userdata           = "echo foo bar"
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_two.id]
      asg_desired_capacity          = 1
    },
  ]

#  worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
#  map_roles                            = var.map_roles
#  map_users                            = var.map_users
#  map_accounts                         = var.map_accounts
}


#################################################################################
#
# Stackable nodes and stuff 
#
# The following resources are added to the AWS EKS cluster to set up a Stackable
# cluster inside the managed K8s cluster
#
#################################################################################

# create a key pair and save it to disk
# this key pair allows full access to the nodes

resource "tls_private_key" "cluster_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "cluster_private_key" { 
  filename = "cluster_key"
  content = tls_private_key.cluster_key.private_key_pem
  file_permission = "0400"
}

resource "local_file" "cluster_public_key" { 
  filename = "cluster_key.pub"
  content = tls_private_key.cluster_key.public_key_openssh
  file_permission = "0440"
}

resource "aws_key_pair" "cluster_keypair" {
  key_name = "${var.aws_eks_cluster_name}-cluster-key"
  public_key = tls_private_key.cluster_key.public_key_openssh
}

# security group for Stackable nodes
resource "aws_security_group" "stackable_nodes" {
  name = "${var.aws_eks_cluster_name}-security-group-stackable-nodes"
  description = "Allows all traffic"
  vpc_id = module.vpc.vpc_id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
  tags = {
    "Name" = "${var.aws_eks_cluster_name}-security-group-stackable-nodes"
  }
}

# orchestrator node
resource "aws_instance" "orchestrator" {
  instance_type = "t2.xlarge"
  ami = "ami-06ec8443c2a35b0ba"
  subnet_id = module.vpc.public_subnets[0]
  security_groups = [aws_security_group.stackable_nodes.id]
  key_name = aws_key_pair.cluster_keypair.key_name
  disable_api_termination = false
  ebs_optimized = false
  root_block_device {
    volume_size = 50
    volume_type = "gp2"
    tags = {
      "Name" = "${var.aws_eks_cluster_name}-orchestrator-disk"
    }
  }
  tags = {
    "Name" = "${var.aws_eks_cluster_name}-orchestrator"
  }
}

# Stackable (agent) nodes
resource "aws_instance" "nodes" {
  count = 5
  instance_type = "t2.medium"
  ami = "ami-06ec8443c2a35b0ba"
  subnet_id = module.vpc.public_subnets[count.index % length(module.vpc.public_subnets)]
  security_groups = [aws_security_group.stackable_nodes.id]
  key_name = aws_key_pair.cluster_keypair.key_name
  disable_api_termination = false
  ebs_optimized = false
  root_block_device {
    volume_size = 50
    volume_type = "gp2"
    tags = {
      "Name" = "${var.aws_eks_cluster_name}-node-${count.index}-disk"
    }
  }
  tags = {
    "Name" = "${var.aws_eks_cluster_name}-node-${count.index}"
  }
}

# inventory file for Ansible
resource "local_file" "ansible-inventory" {
  filename = "ansible/inventory/inventory"
  content = templatefile("templates/ansible-inventory.tpl",
    {
      nodes = aws_instance.nodes
      orchestrator = aws_instance.orchestrator
      ssh_key_private_path = local_file.cluster_private_key.filename
      cluster_name = var.aws_eks_cluster_name
    }
  )
  file_permission = "0440"
} 


