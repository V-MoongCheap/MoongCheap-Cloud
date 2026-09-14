# 팀 Secret Store 결정(AWS Secrets Manager, cloud-infra-architecture.md)에 따라
# Cloudflare API Token / Discord Webhook URL은 여기서 직접 만들지 않고 미리 등록된
# 값을 조회만 한다. 값 자체가 시크릿이라 Terraform 변수(TF_VAR_...)로 매번 손으로
# 넣는 대신, 최초 1회만 아래 명령으로 등록해두면 이후 apply는 자동으로 읽어간다.
#
#   aws secretsmanager create-secret \
#     --name infra-cloudflare-api-token-secret \
#     --secret-string "<Cloudflare API Token>" \
#     --profile moongcheap --region ap-northeast-2
#
#   aws secretsmanager create-secret \
#     --name infra-discord-webhook-secret \
#     --secret-string "<Discord Webhook URL>" \
#     --profile moongcheap --region ap-northeast-2
#
# apply를 실행하는 IAM 주체에는 이 두 시크릿에 대한 secretsmanager:GetSecretValue +
# kms:Decrypt(alias/aws/secretsmanager) 권한이 있어야 한다.
data "aws_secretsmanager_secret_version" "cloudflare_api_token" {
  secret_id = "infra-cloudflare-api-token-secret"
}

data "aws_secretsmanager_secret_version" "discord_webhook" {
  secret_id = "infra-discord-webhook-secret"
}
