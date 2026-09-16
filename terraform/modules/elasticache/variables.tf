variable "project" {
  type        = string
  description = "프로젝트 이름"
  default     = "moongcheap"
}

variable "env" {
  type        = string
  description = "환경 구분 (develop/prod)"
}

variable "vpc_id" {
  type        = string
  description = "Redis Security Group을 생성할 VPC ID"
}

variable "be_ai_security_group_id" {
  type        = string
  description = "6379 Inbound를 허용할 BE·AI Worker Node Group Security Group ID"
}

# RDS와 동일한 격리 수준(DB Private Subnet)에 배치한다 — 문서에 Redis 전용 Subnet
# 계층이 별도로 명시되어 있지 않아, RDS/OpenSearch와 같은 데이터 계층으로 취급한다.
variable "subnet_ids" {
  type        = list(string)
  description = "ElastiCache Subnet Group에 사용할 Subnet ID 목록 (DB Private Subnet, modules/vpc 출력값)"
}

# naming_convention_V2.md 3.8 확정 스펙
variable "node_type" {
  type        = string
  description = "ElastiCache 노드 타입"
  default     = "cache.t4g.small"
}

variable "num_cache_clusters" {
  type        = number
  description = "노드 개수 (Primary + Replica)"
  default     = 2
}

variable "engine_version" {
  type        = string
  description = "Redis 엔진 버전"
  default     = "7.1"
}
