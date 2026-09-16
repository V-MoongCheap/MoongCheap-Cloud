output "primary_endpoint" {
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
  description = "Redis Primary 접속 엔드포인트"
}

output "reader_endpoint" {
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
  description = "Redis Reader(Replica) 접속 엔드포인트"
}

output "port" {
  value       = 6379
  description = "Redis 접속 포트"
}

output "security_group_id" {
  value       = aws_security_group.redis.id
  description = "Redis Security Group ID"
}
