variable "project" {
  type        = string
  description = "프로젝트 이름"
  default     = "moongcheap"
}

variable "services" {
  type        = list(string)
  description = "서비스 이름"
  default     = ["frontend", "backend", "ai"]
}