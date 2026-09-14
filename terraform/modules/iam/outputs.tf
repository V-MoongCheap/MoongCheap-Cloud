output "cluster_role_arn" {
  value       = aws_iam_role.eks_cluster.arn
  description = "EKS 클러스터(컨트롤 플레인)용 IAM Role ARN"
}

output "node_role_arn" {
  value       = aws_iam_role.eks_node_group.arn
  description = "EKS Worker Node용 IAM Role ARN"
}
