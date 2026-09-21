output "cluster_role_arn" {
  value       = aws_iam_role.eks_cluster.arn
  description = "EKS 클러스터(컨트롤 플레인)용 IAM Role ARN"
}

output "node_role_arn" {
  value       = aws_iam_role.eks_node_group.arn
  description = "EKS Worker Node용 IAM Role ARN"
}

output "node_role_name" {
  value       = aws_iam_role.eks_node_group.name
  description = "EKS Worker Node용 IAM Role 이름 (modules/karpenter가 Instance Profile을 만들 때 참조)"
}

# D-30: 호출부가 module 단위 depends_on 없이 "정책 attachment가 끝난 뒤 EKS 생성" 순서를
# 만들 수 있도록 attachment ID 목록을 내보낸다. modules/eks는 이 목록을 참조만 하고
# 값은 쓰지 않는다(길이만 확인) — 그래서 iam 쪽 변경이 Role ARN을 unknown으로 만들지 않는다.
output "cluster_role_policy_attachment_ids" {
  value       = [aws_iam_role_policy_attachment.eks_cluster_policy.id]
  description = "EKS 클러스터 Role에 붙은 정책 attachment ID 목록 (modules/eks 암묵 의존용)"
}

output "node_role_policy_attachment_ids" {
  value = [
    aws_iam_role_policy_attachment.eks_node_worker_policy.id,
    aws_iam_role_policy_attachment.eks_node_cni_policy.id,
    aws_iam_role_policy_attachment.eks_node_ecr_readonly.id,
    aws_iam_role_policy_attachment.eks_node_ssm.id,
  ]
  description = "EKS Worker Node Role에 붙은 정책 attachment ID 목록 (modules/eks 암묵 의존용)"
}
