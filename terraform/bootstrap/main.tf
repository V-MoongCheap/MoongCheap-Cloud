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

# budget_alert/discord_secret 모듈은 여기 두지 않는다.
# 이 디렉토리는 순환 문제(버킷 자체를 만드는 코드) 때문에 remote backend를 못 쓰고
# state를 Git에 커밋하는 예외 대상인데, Discord Webhook URL 같은 Secret 값을 쓰는
# 리소스를 여기서 apply하면 그 값이 state에 평문으로 박힌 채 커밋된다
# (sensitive=true는 CLI 출력만 가릴 뿐 state 파일 내용은 못 가림 — 2026-09-16 실제로
# 겪은 사고: docs/2026-09-16-feature-status-and-review.md 참고).
# 그래서 remote backend를 쓰는 envs/develop/main.tf로 옮겼다.
