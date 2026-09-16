resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project}-${var.env}-redis-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.project}-${var.env}-redis-subnet-group"
  }
}

# naming_convention_V2.md 3.2: Source Security Group 기반 허용 우선.
resource "aws_security_group" "redis" {
  name        = "${var.project}-${var.env}-redis-sg"
  description = "ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from BE-AI Worker"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.be_ai_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-redis-sg"
  }
}

# naming_convention_V2.md 3.8: Redis OSS / cache.t4g.small x2 / On-Demand.
# Cluster Mode를 쓰지 않는 Replication Group으로 Primary+Replica 2대 구성.
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project}-${var.env}-redis"
  description          = "${var.project} ${var.env} Redis (Cache/Session)"

  # 설계서_V2 6.6·Runbook 10장: ElastiCache는 일반 Destroy 대상에서 제외해야 하는
  # 리소스다. aws_elasticache_replication_group에는 deletion_protection 인자가 없어서
  # (Terraform AWS Provider 스키마로 확인함) prevent_destroy로 동일한 효과를 낸다.
  # 프로젝트 종료 후 정리할 때는 이 블록을 지우거나 false로 바꿔 apply한 뒤 destroy한다.
  lifecycle {
    prevent_destroy = true
  }

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  num_cache_clusters = var.num_cache_clusters

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  automatic_failover_enabled = var.num_cache_clusters > 1

  tags = {
    Name = "${var.project}-${var.env}-redis"
  }
}
