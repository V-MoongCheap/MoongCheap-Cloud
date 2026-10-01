output "controller_role_arn" {
  value       = aws_iam_role.controller.arn
  description = "Karpenter 컨트롤러 IRSA Role ARN — Helm values(serviceAccount.annotations)에 eks.amazonaws.com/role-arn으로 전달"
}

output "node_instance_profile_name" {
  value       = aws_iam_instance_profile.node.name
  description = "EC2NodeClass.spec.instanceProfile에 넣을 Instance Profile 이름"
}

output "node_role_arn" {
  value       = aws_iam_role.node.arn
  description = "Karpenter 전용 노드 Role ARN (참고용 — EC2NodeClass는 Role이 아니라 위 instanceProfile 이름을 참조)"
}

output "discovery_tag_value" {
  value       = var.cluster_name
  description = "EC2NodeClass의 subnetSelectorTerms/securityGroupSelectorTerms가 찾을 karpenter.sh/discovery 태그 값 (클러스터 이름과 동일)"
}
