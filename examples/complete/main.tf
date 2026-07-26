# =============================================================================
# Complete Example — EKS Module
# =============================================================================
# Provisions a production-style EKS cluster composed with the companion VPC
# module:
#   - Dedicated VPC with private subnets for the cluster
#   - EKS control plane with private API access
#   - Two managed node groups: on-demand "general" and cost-saving "spot"
#   - Cluster autoscaler Pod Identity enabled
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "github.com/1solomonwakhungu/terraform-aws-vpc?ref=v1.0.0"

  name            = "eks-prod"
  cidr            = "10.30.0.0/16"
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets  = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]
  private_subnets = ["10.30.101.0/24", "10.30.102.0/24", "10.30.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false

  tags = {
    Environment = "production"
    Cluster     = "eks-prod"
  }
}

module "eks" {
  source = "../../"

  name               = "eks-prod"
  kubernetes_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Restrict the public API endpoint to the corporate CIDR range.
  cluster_endpoint_public_access       = false
  cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]

  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  enable_cluster_autoscaler = true

  node_groups = {
    general = {
      instance_types = ["t3.large"]
      desired_size   = 3
      min_size       = 2
      max_size       = 6
      disk_size      = 50
      capacity_type  = "ON_DEMAND"
    }
    spot = {
      instance_types = ["t3.large", "t3.xlarge"]
      desired_size   = 2
      min_size       = 0
      max_size       = 8
      disk_size      = 50
      capacity_type  = "SPOT"
    }
  }

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.eks.cluster_endpoint
}

output "node_group_names" {
  description = "Names of the managed node groups"
  value       = module.eks.node_group_names
}
