output "endpoint" {
  value       = aws_opensearch_domain.this.endpoint
  description = "OpenSearch 접속 엔드포인트"
}

output "security_group_id" {
  value       = aws_security_group.opensearch.id
  description = "OpenSearch Security Group ID"
}

output "credentials_secret_arn" {
  value       = aws_secretsmanager_secret.opensearch.arn
  description = "Master 계정 정보가 담긴 Secrets Manager Secret ARN"
}
