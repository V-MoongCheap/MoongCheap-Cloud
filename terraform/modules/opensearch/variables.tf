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
  description = "OpenSearch Security Group을 생성할 VPC ID"
}

variable "be_ai_security_group_id" {
  type        = string
  description = "443 Inbound를 허용할 BE·AI Worker Node Group Security Group ID"
}

# RDS와 동일한 격리 수준(DB Private Subnet)에 배치한다 — 문서에 OpenSearch 전용 Subnet
# 계층이 별도로 명시되어 있지 않아, RDS/ElastiCache와 같은 데이터 계층으로 취급한다.
# instance_count=1(단일 AZ)이라 첫 번째 Subnet 하나만 사용한다.
variable "subnet_id" {
  type        = string
  description = "OpenSearch를 배치할 DB Private Subnet ID (단일 AZ, modules/vpc 출력값의 첫 번째 요소)"
}

# naming_convention_V2.md 3.9 확정 스펙
variable "instance_type" {
  type        = string
  description = "OpenSearch 인스턴스 타입"
  default     = "t3.small.search"
}

variable "instance_count" {
  type        = number
  description = "OpenSearch 노드 개수"
  default     = 1
}

variable "ebs_volume_size" {
  type        = number
  description = "노드당 EBS 볼륨 크기(GiB)"
  default     = 10
}

variable "ebs_iops" {
  type        = number
  description = "gp3 볼륨 IOPS"
  default     = 3000
}

variable "engine_version" {
  type        = string
  description = "OpenSearch 엔진 버전"
  default     = "OpenSearch_2.15"
}

variable "master_username" {
  type        = string
  description = "OpenSearch Master 사용자명"
  default     = "moongcheap_admin"
}

# Secrets Manager는 삭제해도 기본 30일 복구 대기 상태로 남아, 같은 이름으로 재생성하려는
# 다음 apply가 "이미 삭제 예정으로 스케줄된 시크릿" 에러로 막힌다. personal-test처럼 자주
# destroy/apply를 반복하는 환경에서는 0으로 둬서 즉시 완전 삭제되게 한다.
variable "secret_recovery_window_in_days" {
  type        = number
  description = "Master 계정 Secret 삭제 시 복구 대기 기간(일). 0이면 즉시 완전 삭제(복구 불가)"
  default     = 7
}
