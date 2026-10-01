variable "aws_profile" {
  type        = string
  description = "AWS CLI Profile Name"
  default     = "moongcheap"
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare 계정 ID"
}

variable "cloudflare_zone_id" {
  type        = string
  description = "도메인이 등록된 Cloudflare Zone ID"
}

variable "cloudflare_subdomain" {
  type        = string
  description = "서비스에 연결할 서브도메인 (루트 도메인이면 빈 문자열)"
  default     = ""
}
