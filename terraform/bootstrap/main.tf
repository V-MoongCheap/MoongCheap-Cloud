# S3 버킷 생성 - 상태 파일(.tfstate) 저장용
resource "aws_s3_bucket" "tfstate_bucket" {
  bucket        = "moongcheap-tfstate"
  force_destroy = false # 실수로 상태 파일이 담긴 버킷이 통째로 날아가는 것을 방지

  lifecycle {
    prevent_destroy = true
  }
}

# S3 버전 관리 활성화 (틀어지거나 유실되었을 때 과거 상태로 복구하기 위해 필수)
resource "aws_s3_bucket_versioning" "tfstate_versioning" {
  bucket = aws_s3_bucket.tfstate_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 서버 사이드 암호화 설정 (민감한 인프라 정보 암호화 보호)
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_crypto" {
  bucket = aws_s3_bucket.tfstate_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 버킷 정의 아래 — 퍼블릭 접근 전면 차단 (state 버킷이라 필수)
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 계정 전체 총 사용 금액 하나만 감시하면 되는 리소스라 develop/prod 어느 한쪽에
# 속하지 않는다. envs/*에서 각각 호출하면 env 변수가 없는 budget-alert 모듈 특성상
# 이름 충돌이 나고, develop→prod 전환 중 예산 감시가 끊기므로 여기서 한 번만 만든다.
module "discord_secret" {
  source    = "../modules/secrets"
  secret_id = "moongcheap-develop-infra-discord-secret"
}

module "budget_alert" {
  source = "../modules/budget-alert"

  discord_webhook_url = module.discord_secret.secret_string
}
