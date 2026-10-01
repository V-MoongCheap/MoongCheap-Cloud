output "db_instance_id" {
  value       = aws_db_instance.this.id
  description = "생성된 RDS 인스턴스 ID"
}

output "db_endpoint" {
  value       = aws_db_instance.this.address
  description = "RDS 접속 호스트(포트 제외)"
}

output "db_port" {
  value       = aws_db_instance.this.port
  description = "RDS 접속 포트"
}

output "security_group_id" {
  value       = aws_security_group.rds.id
  description = "RDS Security Group ID"
}

output "credentials_secret_arn" {
  value       = aws_secretsmanager_secret.db.arn
  description = "DB 접속 정보(host/port/dbname/username/password)가 담긴 Secrets Manager Secret ARN"
}
