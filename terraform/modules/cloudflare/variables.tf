variable "project" {
  type        = string
  description = "프로젝트 이름"
  default     = "moongcheap"
}

variable "env" {
  type        = string
  description = "환경 구분 (develop/prod)"
}

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

# C-12 / J-3: 서비스별 호스트 확장. 기존 `subdomain`(레코드 1개)은 그대로 두고
# 여기 나열한 서브도메인마다 같은 Tunnel을 가리키는 CNAME을 추가로 만든다.
# 기존 subdomain을 list로 바꾸지 않는 이유: 이미 존재하는 cloudflare_record.tunnel의
# 주소(리소스 키)가 바뀌면 Terraform이 삭제 후 재생성 → 그 사이 도메인이 끊긴다.
# 값은 zone 기준 상대 이름이다 (예: "api" → api.<zone>, "api.moongcheap" → api.moongcheap.<zone>).
variable "extra_subdomains" {
  type        = list(string)
  description = "Tunnel에 추가로 연결할 서브도메인 목록 (zone 기준 상대 이름). 비우면 아무것도 안 만든다"
  default     = []
}


variable "secret_recovery_window_in_days" {
  type        = number
  description = "Cloudflare Tunnel Token Secret 삭제 시 복구 대기 기간(일). 0이면 즉시 완전 삭제(복구 불가)"
  default     = 7
}