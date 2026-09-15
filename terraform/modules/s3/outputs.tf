output "bucket_id" {
  value       = aws_s3_bucket.object.id
  description = "생성된 S3 버킷 이름"
}

output "bucket_arn" {
  value       = aws_s3_bucket.object.arn
  description = "생성된 S3 버킷 ARN (IAM 정책에서 참조)"
}
