data "aws_caller_identity" "current" {}

locals {
  tags = merge({
    "terraform:module" = "eks"
    "managed:by"       = "terraform"
  }, var.tags)

  cluster_name = var.name
}

# EKS Cluster IAM Role
resource "aws_iam_role" "cluster" {
  name = "${local.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# Security Group for Cluster
resource "aws_security_group" "cluster" {
  name        = "${local.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster ${local.cluster_name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.cluster_security_group_ingress_cidrs) == 0 ? [] : [1]

    content {
      description = "Allow explicitly trusted networks to reach the control plane"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.cluster_security_group_ingress_cidrs
    }
  }

  dynamic "egress" {
    for_each = length(var.cluster_security_group_egress_cidrs) == 0 ? [] : [1]

    content {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = var.cluster_security_group_egress_cidrs
    }
  }

  tags = merge(local.tags, {
    Name = "${local.cluster_name}-cluster-sg"
  })
}

# CloudWatch Log Group for control plane logs
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 30

  tags = local.tags
}

resource "aws_kms_key" "cluster_secrets" {
  description             = "KMS key for EKS cluster secret encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_alias" "cluster_secrets" {
  name          = "alias/${local.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.cluster_secrets.key_id
}

# EKS Cluster
resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    endpoint_private_access = true
    security_group_ids      = [aws_security_group.cluster.id]
  }

  enabled_cluster_log_types = var.cluster_enabled_log_types

  encryption_config {
    provider {
      key_arn = aws_kms_key.cluster_secrets.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = merge(local.tags, {
    Name = local.cluster_name
  })
}

# Node Group IAM Role
resource "aws_iam_role" "node_group" {
  name = "${local.cluster_name}-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# Managed Node Groups
resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-${each.key}"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  disk_size      = each.value.disk_size
  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type

  tags = merge(local.tags, {
    Name = "${local.cluster_name}-${each.key}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_autoscaling_group_tag" "cluster_autoscaler" {
  for_each = var.enable_cluster_autoscaler ? merge([
    for node_group_name in keys(var.node_groups) : {
      for tag_key, tag_value in {
        "k8s.io/cluster-autoscaler/enabled"               = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
        } : "${node_group_name}:${tag_key}" => {
        node_group_name = node_group_name
        key             = tag_key
        value           = tag_value
      }
    }
  ]...) : {}

  autoscaling_group_name = aws_eks_node_group.this[each.value.node_group_name].resources[0].autoscaling_groups[0].name

  tag {
    key                 = each.value.key
    value               = each.value.value
    propagate_at_launch = false
  }
}

# Cluster Autoscaler Pod Identity (optional)
resource "aws_iam_role" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  name  = "${local.cluster_name}-cluster-autoscaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "sts:AssumeRole",
        "sts:TagSession",
      ]
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_policy" "cluster_autoscaler" {
  count       = var.enable_cluster_autoscaler ? 1 : 0
  name        = "${local.cluster_name}-cluster-autoscaler-policy"
  description = "IAM policy for cluster autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
        ]
        Effect   = "Allow"
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = var.enable_cluster_autoscaler ? 1 : 0
  policy_arn = aws_iam_policy.cluster_autoscaler[0].arn
  role       = aws_iam_role.cluster_autoscaler[0].name
}

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  count           = var.enable_cluster_autoscaler ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.cluster_autoscaler_namespace
  service_account = var.cluster_autoscaler_service_account
  role_arn        = aws_iam_role.cluster_autoscaler[0].arn
}
