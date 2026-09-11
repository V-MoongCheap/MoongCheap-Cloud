# 팀 Secret Store 결정(AWS Secrets Manager)에 따라, 값 자체가 시크릿인 것들은
# Terraform 변수(TF_VAR_...)로 매번 손으로 넣는 대신 미리 등록된 값을 조회만 한다.
# 이 모듈은 생성이 아니라 조회 전용이다 — naming_convention_V2.md의 Secret Naming
# 규칙(`moongcheap-{env}-{service}-{purpose}-secret`)에 맞춰 미리 등록해둬야 한다.
#
#   aws secretsmanager create-secret \
#     --name <secret_id> \
#     --secret-string "<값>" \
#     --profile moongcheap --region ap-northeast-2
#
# apply를 실행하는 IAM 주체에는 secretsmanager:GetSecretValue +
# kms:Decrypt(alias/aws/secretsmanager) 권한이 있어야 한다.
data "aws_secretsmanager_secret_version" "this" {
  secret_id = var.secret_id
}
