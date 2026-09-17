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

# ── 이하 gitops 인계값 (C-1) ─────────────────────────────────────────────
# gitops/의 REPLACE_ME / <AWS_ACCOUNT_ID> / [배포후_도메인_기입] 자리를 채울 때 쓰는 값.
# Terraform이 gitops 파일을 직접 갱신하지는 않는다 — `terraform output`으로 읽어서
# gitops/에 커밋(비밀 아닌 값) 또는 K8s Secret으로 주입(tunnel_token)한다.
# Workload IRSA Role ARN(jenkins/be/ai)은 Role이 아직 없어 제외 — C-5 이후 추가.

output "aws_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "gitops/jenkins/pipelines/Jenkinsfile.template의 ECR_REGISTRY(<AWS_ACCOUNT_ID>.dkr.ecr...)에 넣을 값"
}

output "ecr_repository_urls" {
  value       = module.ecr.repository_urls
  description = "gitops/values/services/{frontend,backend,ai}.yaml의 image.repository(REPLACE_ME/*)에 넣을 값"
}

output "redis_primary_endpoint" {
  value       = module.elasticache.primary_endpoint
  description = "BE/AI 환경변수 REDIS_HOST (네이밍 9.3). ElastiCache는 Secret을 안 만들어서 이 output이 유일한 경로"
}

output "redis_port" {
  value       = module.elasticache.port
  description = "BE/AI 환경변수 REDIS_PORT"
}

output "opensearch_endpoint" {
  value       = module.opensearch.endpoint
  description = "BE/AI 환경변수 OPENSEARCH_URL (네이밍 9.3). opensearch-secret엔 username/password만 있고 endpoint는 없음"
}

output "s3_object_bucket" {
  value       = module.s3.bucket_id
  description = "BE 환경변수 S3_BUCKET_NAME (네이밍 9.3)"
}

output "cloudflare_fqdn" {
  value       = module.cloudflare.fqdn
  description = "gitops/platform/jenkins/values.yaml의 ingress.hostName 등 [배포후_도메인_기입] 자리에 넣을 도메인"
}

# 비밀값. `terraform output` 목록에선 가려지고 `terraform output -raw cloudflare_tunnel_token`으로만 꺼낸다.
# gitops/에 커밋하거나 Discord 등에 붙여넣지 말 것 — cloudflared용 K8s Secret 생성에만 사용.
output "cloudflare_tunnel_token" {
  value       = module.cloudflare.tunnel_token
  description = "cloudflared Deployment가 쓰는 Tunnel 토큰 (sensitive)"
  sensitive   = true
}
