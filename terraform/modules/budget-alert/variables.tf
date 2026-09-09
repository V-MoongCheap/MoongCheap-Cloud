variable "project" {
  description = "프로젝트 이름 (네이밍 규약 기준)"
  type        = string
  default     = "moongcheap"
}

variable "discord_webhook_url" {
  description = "Discord #비용-알림 채널 웹훅 URL"
  type        = string
  sensitive   = true
}

variable "monthly_budget_limit_usd" {
  description = "월별 예산 한도 (USD)"
  type        = string
  default     = "552"
}

variable "budget_notification_thresholds" {
  description = "예산 대비 알림을 보낼 임계값(%) 목록"
  type        = list(number)
  default     = [50, 80, 100]
}
