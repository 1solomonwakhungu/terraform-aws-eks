variable "name" {
  description = "Name prefix for all EKS resources"
  type        = string
  default     = "my-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster (recommend private subnets)"
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Whether the cluster API endpoint is publicly accessible"
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to access the public cluster endpoint"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "cluster_security_group_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the private cluster control-plane security group on port 443"
  type        = list(string)
  default     = []
}

variable "cluster_security_group_egress_cidrs" {
  description = "CIDR blocks the custom control-plane security group may reach; leave empty to rely on the EKS-managed cluster security group"
  type        = list(string)
  default     = []
}

variable "cluster_enabled_log_types" {
  description = "List of control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "node_groups" {
  description = "Map of managed node group configurations"
  type = map(object({
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size      = optional(number, 50)
    capacity_type  = optional(string, "ON_DEMAND")
  }))
  default = {
    general = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      disk_size      = 50
      capacity_type  = "ON_DEMAND"
    }
  }
}

variable "enable_cluster_autoscaler" {
  description = "Whether to create a least-privilege EKS Pod Identity role and association for cluster autoscaler"
  type        = bool
  default     = false
}

variable "cluster_autoscaler_namespace" {
  description = "Kubernetes namespace containing the cluster autoscaler service account"
  type        = string
  default     = "kube-system"
}

variable "cluster_autoscaler_service_account" {
  description = "Kubernetes service account used by cluster autoscaler"
  type        = string
  default     = "cluster-autoscaler"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
