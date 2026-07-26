provider "aws" {
  region = "us-east-1"
}

# Reference: Assumes a VPC module has been deployed
# module "vpc" {
#   source = "../../vpc"
#   ...
# }

module "eks" {
  source = "../.."

  name               = "example-eks"
  kubernetes_version = "1.34"
  vpc_id             = "vpc-12345678"
  subnet_ids         = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]

  enable_cluster_autoscaler = true

  node_groups = {
    general = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 1
      max_size       = 4
    }
  }

  tags = {
    Environment = "example"
    Owner       = "solomon"
  }
}
