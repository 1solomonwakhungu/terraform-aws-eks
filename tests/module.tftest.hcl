mock_provider "aws" {}

override_resource {
  target          = aws_eks_cluster.this
  override_during = plan

  values = {
    id       = "per237-eks"
    arn      = "arn:aws:eks:us-east-1:123456789012:cluster/per237-eks"
    endpoint = "https://example.eks.amazonaws.com"

    certificate_authority = [{
      data = "dGVzdA=="
    }]
  }
}

run "plans_cluster_and_node_groups" {
  command = plan

  variables {
    name               = "per237-eks"
    kubernetes_version = "1.29"
    vpc_id             = "vpc-0123456789abcdef0"

    subnet_ids = [
      "subnet-0123456789abcdef0",
      "subnet-0123456789abcdef1",
    ]

    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = ["198.51.100.0/24"]
    cluster_enabled_log_types            = ["api", "audit"]
    enable_cluster_autoscaler            = true

    node_groups = {
      general = {
        instance_types = ["t3.large"]
        desired_size   = 3
        min_size       = 2
        max_size       = 6
        disk_size      = 80
        capacity_type  = "ON_DEMAND"
      }
      spot = {
        instance_types = ["t3.large", "t3.xlarge"]
        desired_size   = 1
        min_size       = 0
        max_size       = 4
        capacity_type  = "SPOT"
      }
    }

    tags = {
      Environment = "test"
      Owner       = "platform"
    }
  }

  assert {
    condition     = aws_eks_cluster.this.name == "per237-eks"
    error_message = "The EKS cluster must use the requested name."
  }

  assert {
    condition     = aws_eks_cluster.this.version == "1.29"
    error_message = "The EKS cluster must use the requested Kubernetes version."
  }

  assert {
    condition = (
      one(aws_eks_cluster.this.vpc_config).endpoint_private_access &&
      one(aws_eks_cluster.this.vpc_config).endpoint_public_access &&
      toset(one(aws_eks_cluster.this.vpc_config).public_access_cidrs) == toset(["198.51.100.0/24"])
    )
    error_message = "Endpoint access must retain private access and apply the requested public CIDR."
  }

  assert {
    condition     = aws_cloudwatch_log_group.cluster.retention_in_days == 30
    error_message = "Control-plane logs must be retained for 30 days."
  }

  assert {
    condition     = aws_eks_cluster.this.enabled_cluster_log_types == toset(["api", "audit"])
    error_message = "The requested control-plane log types must be enabled."
  }

  assert {
    condition     = length(aws_eks_node_group.this) == 2
    error_message = "Every configured node group must produce a managed node group."
  }

  assert {
    condition = (
      one(aws_eks_node_group.this["general"].scaling_config).desired_size == 3 &&
      one(aws_eks_node_group.this["general"].scaling_config).min_size == 2 &&
      one(aws_eks_node_group.this["general"].scaling_config).max_size == 6 &&
      aws_eks_node_group.this["general"].disk_size == 80
    )
    error_message = "General node-group scaling and disk settings must be preserved."
  }

  assert {
    condition = (
      aws_eks_node_group.this["spot"].capacity_type == "SPOT" &&
      aws_eks_node_group.this["spot"].disk_size == 50
    )
    error_message = "Spot capacity and the default disk size must be applied."
  }

  assert {
    condition     = length(aws_iam_policy.cluster_autoscaler) == 1
    error_message = "Enabling autoscaling must create its IAM policy."
  }

  assert {
    condition     = contains(jsondecode(aws_iam_policy.cluster_autoscaler[0].policy).Statement[0].Action, "autoscaling:SetDesiredCapacity")
    error_message = "The autoscaler policy must permit adjusting desired capacity."
  }

  assert {
    condition     = jsondecode(aws_iam_role.cluster.assume_role_policy).Statement[0].Principal.Service == "eks.amazonaws.com"
    error_message = "The cluster IAM role must trust the EKS service."
  }

  assert {
    condition     = jsondecode(aws_iam_role.node_group.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com"
    error_message = "The node-group IAM role must trust EC2."
  }

  assert {
    condition = (
      aws_eks_cluster.this.tags["Environment"] == "test" &&
      aws_eks_cluster.this.tags["managed:by"] == "terraform"
    )
    error_message = "Standard and caller-supplied tags must be applied."
  }

  assert {
    condition     = output.cluster_id == "per237-eks"
    error_message = "The cluster ID output must reference the EKS cluster."
  }
}

run "omits_autoscaler_when_disabled" {
  command = plan

  variables {
    name   = "per237-eks"
    vpc_id = "vpc-0123456789abcdef0"
    subnet_ids = [
      "subnet-0123456789abcdef0",
      "subnet-0123456789abcdef1",
    ]

    enable_cluster_autoscaler = false
  }

  assert {
    condition     = length(aws_iam_policy.cluster_autoscaler) == 0
    error_message = "Disabling autoscaling must omit its IAM policy."
  }

  assert {
    condition     = output.cluster_autoscaler_policy_arn == null
    error_message = "The autoscaler policy output must be null when disabled."
  }
}
