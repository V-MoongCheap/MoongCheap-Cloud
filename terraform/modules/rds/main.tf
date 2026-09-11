resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.env}-db-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "${var.project}-${var.env}-db-subnet-group"
  }
}

# naming_convention_V2.md 3.2: CIDR 기반 허용보다 Source Security Group 기반 허용을
# 우선한다 — BE·AI Worker Node Group Security Group에서만 5432를 열어준다.
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.env}-rds-sg"
  description = "RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from BE-AI Worker"
    from_port       = 5432
    to_port         = 5432
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
    Name = "${var.project}-${var.env}-rds-sg"
  }
}

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_db_instance" "this" {
  identifier     = "${var.project}-${var.env}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  multi_az = var.multi_az

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # 아키텍처 설계서_V2 6.2: Public Access 비활성화 — 인터넷에서 직접 접근 불가.
  publicly_accessible = false

  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection

  tags = {
    Name = "${var.project}-${var.env}-postgres"
  }
}

# pgvector는 RDS 리소스 속성이 아니라 DB 접속 후 실행하는 SQL Extension이라
# Terraform으로 직접 만들 수 없다. RDS가 뜬 뒤 한 번 아래 SQL을 실행해야 한다.
#   CREATE EXTENSION IF NOT EXISTS vector;
# naming_convention_V2.md: DB Secret은 moongcheap-{env}-db-secret 하나로 통일하고
# BE·AI Pod가 전부 이 Secret을 조회한다.
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}-${var.env}-db-secret"
  recovery_window_in_days = var.secret_recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.db_name
    username = var.master_username
    password = random_password.master.result
  })
}
