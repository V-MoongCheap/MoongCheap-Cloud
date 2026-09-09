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
