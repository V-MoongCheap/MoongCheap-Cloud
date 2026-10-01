output "secret_string" {
  value       = data.aws_secretsmanager_secret_version.this.secret_string
  description = "조회된 Secret 값"
  sensitive   = true
}
