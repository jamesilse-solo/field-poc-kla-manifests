variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
  default     = "986112284769"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "kla-agentic-cluster"
}

variable "node_instance_type" {
  description = "Instance type for EKS nodes"
  type        = string
  default     = "t3.large"
}

variable "node_count" {
  description = "Number of nodes in the node group"
  type        = number
  default     = 3
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.2.0.0/16"
}
