# EKS Module

A production-grade Terraform module for creating AWS EKS clusters with managed node groups.

## Features

- EKS cluster with configurable Kubernetes version
- Managed node groups (configurable instance types, scaling, capacity type)
- IAM roles and policies for cluster and node groups
- Security group for cluster control plane
- Control plane logging to CloudWatch
- Optional cluster autoscaler IAM policy
- Consistent tagging across all resources

## Usage

```hcl
module "eks" {
  source = "./modules/eks"

  name                = "production-eks"
  kubernetes_version  = "1.29"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids

  cluster_endpoint_public_access = true
  cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]

  enable_cluster_autoscaler = true

  node_groups = {
    general = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 1
      max_size       = 4
    }
    spot = {
      instance_types = ["t3.large", "t3.xlarge"]
      desired_size   = 1
      min_size       = 0
      max_size       = 3
      capacity_type  = "SPOT"
    }
  }

  tags = {
    Environment = "production"
    Owner       = "platform-team"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all EKS resources | `string` | `"my-eks"` | No |
| kubernetes_version | Kubernetes version for the EKS cluster | `string` | `"1.29"` | No |
| vpc_id | ID of the VPC where the EKS cluster will be deployed | `string` | n/a | Yes |
| subnet_ids | List of subnet IDs for the EKS cluster | `list(string)` | n/a | Yes |
| cluster_endpoint_public_access | Whether the cluster API endpoint is publicly accessible | `bool` | `true` | No |
| cluster_endpoint_public_access_cidrs | List of CIDR blocks allowed to access the public cluster endpoint | `list(string)` | `["0.0.0.0/0"]` | No |
| cluster_enabled_log_types | List of control plane log types to enable | `list(string)` | `["api", "audit", "authenticator", "controllerManager", "scheduler"]` | No |
| node_groups | Map of managed node group configurations | `map(object)` | `{ general = { ... } }` | No |
| enable_cluster_autoscaler | Whether to create IAM policy for cluster autoscaler | `bool` | `false` | No |
| tags | Additional tags to apply to all resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | The name/ID of the EKS cluster |
| cluster_arn | The ARN of the EKS cluster |
| cluster_endpoint | Endpoint for the EKS Kubernetes API |
| cluster_certificate_authority_data | Base64 encoded certificate data for communicating with the cluster |
| cluster_security_group_id | Security group ID associated with the cluster |
| cluster_iam_role_arn | IAM role ARN of the EKS cluster |
| cluster_iam_role_name | IAM role name of the EKS cluster |
| node_group_iam_role_arn | IAM role ARN of the node groups |
| node_group_iam_role_name | IAM role name of the node groups |
| node_group_names | Names of the created node groups |
| cluster_autoscaler_policy_arn | ARN of the cluster autoscaler IAM policy (if enabled) |
