variable "account_id" {
  type        = string
  description = "Cloudflare 계정 ID (대시보드 우측 사이드바에서 확인)"
}

variable "zone_id" {
  type        = string
  description = "도메인이 등록된 Cloudflare Zone ID (대시보드 도메인 개요 페이지 우측 사이드바에서 확인)"
}

variable "tunnel_name" {
  type        = string
  description = "Cloudflare Tunnel 이름"
  default     = "moongcheap"
}

variable "subdomain" {
  type        = string
  description = "서비스에 연결할 서브도메인. 루트 도메인에 연결하려면 빈 문자열(\"\")로 둔다 (예: \"www\" -> www.example.com)"
  default     = ""
}
