output "cluster_name" {
  value       = aws_eks_cluster.this.name
  description = "EKS 클러스터 이름 (M6 Node Group에서 사용)"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.this.endpoint
  description = "EKS API 서버 엔드포인트"
}

output "cluster_certificate_authority_data" {
  value       = aws_eks_cluster.this.certificate_authority[0].data
  description = "kubeconfig 구성에 필요한 CA 인증서 데이터"
}

output "cluster_oidc_issuer_url" {
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
  description = "OIDC Issuer URL (M7 IRSA에서 사용)"
}

output "fe_security_group_id" {
  value       = aws_security_group.fe.id
  description = "FE Worker Node Group Security Group ID (Source SG 기반 접근 제어에서 사용)"
}

output "be_ai_security_group_id" {
  value       = aws_security_group.be_ai.id
  description = "BE·AI Worker Node Group Security Group ID (RDS/Redis/OpenSearch Source SG로 사용)"
}

# Managed Node Group과 달리 Karpenter가 직접 launch하는 EC2는 클러스터 SG를 자동으로
# 못 받는다 — 안 붙이면 컨트롤 플레인과 통신이 안 돼 노드가 등록되지 않는다.
output "cluster_security_group_id" {
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description = "EKS 클러스터 SG ID — Karpenter 노드가 컨트롤 플레인과 통신하려면 이 SG도 반드시 붙어있어야 함"
}

output "node_group_names" {
  value = {
    fe = aws_eks_node_group.fe.node_group_name
  }
  description = "생성된 Managed Node Group 이름 목록 (BE·AI는 Karpenter가 대체해서 없음)"
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks.arn
  description = "IAM에 등록된 EKS OIDC Provider ARN (추가 IRSA Role 만들 때 참조)"
}

output "ebs_csi_driver_role_arn" {
  value       = aws_iam_role.ebs_csi_driver.arn
  description = "EBS CSI Driver IRSA Role ARN — EKS Addon 설치 시 서비스 어카운트에 annotation으로 연결해야 함"
}

output "eso_role_arn" {
  value       = aws_iam_role.eso.arn
  description = "External Secrets Operator IRSA Role ARN — Helm Chart의 serviceAccount.annotations에 eks.amazonaws.com/role-arn으로 전달 (K-5)"
}

output "jenkins_role_arn" {
  value       = aws_iam_role.jenkins.arn
  description = "Jenkins IRSA Role ARN — gitops/platform/jenkins/values.yaml serviceAccount.annotations의 eks.amazonaws.com/role-arn (K-2(b))"
}

output "be_role_arn" {
  value       = local.create_be_role ? aws_iam_role.be[0].arn : null
  description = "Backend IRSA Role ARN — 공통 Chart serviceAccount.annotations (K-9). be_s3_bucket_arn을 안 넘기면 null"
}
