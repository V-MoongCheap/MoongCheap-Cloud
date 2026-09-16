output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "kubectl/Helm에서 클러스터를 특정할 때 사용"
}

output "karpenter_controller_role_arn" {
  value       = module.karpenter.controller_role_arn
  description = "Karpenter Helm 설치 시 serviceAccount.annotations에 넣을 IRSA Role ARN"
}

output "karpenter_node_instance_profile_name" {
  value       = module.karpenter.node_instance_profile_name
  description = "EC2NodeClass.spec.instanceProfile에 넣을 값"
}

output "karpenter_discovery_tag_value" {
  value       = module.karpenter.discovery_tag_value
  description = "EC2NodeClass의 subnetSelectorTerms/securityGroupSelectorTerms 태그 값 (클러스터 이름과 동일)"
}
