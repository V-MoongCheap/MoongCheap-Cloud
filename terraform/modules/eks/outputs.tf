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

output "node_group_names" {
  value = {
    fe    = aws_eks_node_group.fe.node_group_name
    be_ai = aws_eks_node_group.be_ai.node_group_name
  }
  description = "생성된 Node Group 이름 목록"
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks.arn
  description = "IAM에 등록된 EKS OIDC Provider ARN (추가 IRSA Role 만들 때 참조)"
}

output "ebs_csi_driver_role_arn" {
  value       = aws_iam_role.ebs_csi_driver.arn
  description = "EBS CSI Driver IRSA Role ARN — EKS Addon 설치 시 서비스 어카운트에 annotation으로 연결해야 함"
}
