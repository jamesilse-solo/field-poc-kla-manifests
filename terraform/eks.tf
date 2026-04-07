resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.35"

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = {
    Name = var.cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = [aws_subnet.private[0].id]

  scaling_config {
    desired_size = var.node_count
    max_size     = var.node_count
    min_size     = var.node_count
  }

  instance_types = [var.node_instance_type]
  capacity_type  = "ON_DEMAND"

  labels = {
    cluster  = "kla-agentic"
    nodepool = "main"
  }

  tags = {
    Name = "${var.cluster_name}-nodes"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
    aws_iam_role_policy_attachment.eks_bedrock_policy,
  ]
}
