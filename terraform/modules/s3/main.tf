# 아키텍처 설계서_V2 6.3: 이미지/파일 등 Object 데이터의 Primary Storage.
# 버킷 이름은 문서에 명시된 규칙(moongcheap-{env}-object)을 그대로 따른다.
# S3 버킷명은 전역으로 유일해야 하므로, 만약 이 이름이 이미 다른 AWS 계정에서 쓰이고
# 있다면 apply 시 BucketAlreadyExists로 실패한다 — 그 경우 계정 ID 등을 덧붙여야 한다.
resource "aws_s3_bucket" "object" {
  bucket = "${var.project}-${var.env}-object"

  tags = {
    Name = "${var.project}-${var.env}-object"
  }
}

resource "aws_s3_bucket_public_access_block" "object" {
  bucket = aws_s3_bucket.object.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 문서상 Versioning/Encryption/Lifecycle은 [확정 필요] 상태다. 안전한 기본값(버저닝+기본
# 암호화 활성화)으로 우선 구성하고, 팀 결정이 나오면 조정한다. 다운그레이드는 언제든 가능.
resource "aws_s3_bucket_versioning" "object" {
  bucket = aws_s3_bucket.object.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "object" {
  bucket = aws_s3_bucket.object.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
