resource "random_password" "master" {
  length  = 20
  special = true
  # OpenSearch Master 비밀번호는 특수문자 허용 폭이 좁아 일부 문자를 제외한다.
  override_special = "!#$%&*()-_=+[]{}"
}

# naming_convention_V2.md 3.2: Source Security Group 기반 허용 우선.
resource "aws_security_group" "opensearch" {
  name        = "${var.project}-${var.env}-opensearch-sg"
  description = "OpenSearch"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from BE-AI Worker"
    from_port       = 443
    to_port         = 443
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
    Name = "${var.project}-${var.env}-opensearch-sg"
  }
}

resource "aws_secretsmanager_secret" "opensearch" {
  name                    = "${var.project}-${var.env}-opensearch-secret"
  recovery_window_in_days = var.secret_recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "opensearch" {
  secret_id = aws_secretsmanager_secret.opensearch.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
  })
}

# naming_convention_V2.md 3.9 확정 스펙: t3.small.search x1, gp3 10GiB, 3000 IOPS.
# VPC 내부 배치라 네트워크(SG)로 접근이 이미 격리되므로, IAM/Cognito 기반 세밀한 인증은
# [확정 필요] 상태로 두고 우선 Fine-grained Access Control(마스터 계정)만 적용한다.
#
# domain_name은 AWS 제약상 최대 28자라, naming_convention_V2.md 표기("moongcheap-{env}-
# opensearch")를 그대로 쓰면 develop부터 초과한다. 글자 수 제약이 있는 domain_name만
# "opensearch" -> "os"로 줄이고 다른 리소스(SG/Secret)는 문서 규칙 그대로 둔다.
resource "aws_opensearch_domain" "this" {
  domain_name    = "${var.project}-${var.env}-os"
  engine_version = var.engine_version

  cluster_config {
    instance_type  = var.instance_type
    instance_count = var.instance_count
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.ebs_volume_size
    iops        = var.ebs_iops
  }

  vpc_options {
    subnet_ids         = [var.subnet_id]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https = true
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.master_username
      master_user_password = random_password.master.result
    }
  }

  tags = {
    Name = "${var.project}-${var.env}-opensearch"
  }
}

# SG로 네트워크를 막아도, 도메인에 리소스 기반 Access Policy가 없으면 Fine-grained
# Access Control(마스터 계정 Basic Auth)까지 거부당한다. VPC 배치로 네트워크는 이미
# 격리돼 있으므로 Access Policy 자체는 넓게 열어도 안전하다.
resource "aws_opensearch_domain_policy" "this" {
  domain_name = aws_opensearch_domain.this.domain_name

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "es:*"
        Resource  = "${aws_opensearch_domain.this.arn}/*"
      }
    ]
  })
}
