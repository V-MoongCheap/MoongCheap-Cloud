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
  description = "RDS Security Group을 생성할 VPC ID"
}

variable "be_ai_security_group_id" {
  type        = string
  description = "5432 Inbound를 허용할 BE·AI Worker Node Group Security Group ID (naming_convention_V2.md 3.2: Source SG 기반 허용 우선, modules/eks 출력값)"
}

variable "db_subnet_ids" {
  type        = list(string)
  description = "DB Subnet Group에 사용할 DB Private Subnet ID 목록 (AZ당 1개 이상, modules/vpc 출력값)"
}

# 아키텍처 설계서_V2 6.2 RDS PostgreSQL + pgvector 스펙
variable "engine_version" {
  type        = string
  description = "PostgreSQL 엔진 버전 (문서상 [확정 필요]). 16.4는 이 계정/리전에 실제로 존재하지 않아 apply가 실패하므로, `aws rds describe-db-engine-versions`로 확인된 실제 가용 버전(16.9)을 기본값으로 둔다."
  default     = "16.9"
}

variable "instance_class" {
  type        = string
  description = "RDS 인스턴스 클래스"
  default     = "db.t4g.medium"
}

variable "allocated_storage" {
  type        = number
  description = "스토리지 크기(GiB)"
  default     = 50
}

variable "multi_az" {
  type        = bool
  description = "Multi-AZ 적용 여부"
  default     = true
}

variable "db_name" {
  type        = string
  description = "초기 생성할 Database 이름 (문서상 [확정 필요], 우선 프로젝트명으로 설정)"
  default     = "moongcheap"
}

variable "master_username" {
  type        = string
  description = "Master DB 사용자명 (문서상 [확정 필요])"
  default     = "moongcheap_admin"
}

# skip_final_snapshot은 반복 테스트 편의를 우선해 기본 true로 둔다 (prod 도입 시
# envs/prod에서 false로 오버라이드할 것 — 아직 prod 디렉토리 자체가 없음).
variable "skip_final_snapshot" {
  type        = bool
  description = "삭제 시 최종 스냅샷 생략 여부"
  default     = true
}

# 설계서_V2 6.6·Runbook 10장: "일반 Destroy 과정에서 데이터가 삭제되지 않도록 보호"를
# 요구하고, develop이 현재 유일한 운영 환경(네이밍 8.1)이라 "prod에서만 켠다" 전제가
# 성립하지 않는다. 실수로 target 없이 destroy하거나 이 resource 블록을 지운 채
# apply해도 RDS 삭제 API 호출 자체가 AWS에서 거부되도록 기본값을 true로 둔다.
# 프로젝트 종료 후 실제로 정리할 때는 이 값을 false로 바꿔 apply한 뒤 destroy한다
# (docs/2026-09-16-feature-status-and-review.md B-6 리뷰 참고).
variable "deletion_protection" {
  type        = bool
  description = "삭제 방지 활성화 여부. 프로젝트 종료 정리 시에는 false로 바꿔 apply 후 destroy할 것"
  default     = true
}

variable "backup_retention_period" {
  type        = number
  description = "자동 백업 보존 기간(일). Free Tier 계정은 0(자동 백업 비활성화)이 아니면 CreateDBInstance가 FreeTierRestrictionError로 거부된다 — personal-test에서는 반드시 0으로 오버라이드."
  default     = 7
}

# Secrets Manager는 삭제해도 기본 30일 복구 대기(pending deletion) 상태로 남아, 같은
# 이름으로 재생성하려는 다음 apply가 "이미 삭제 예정으로 스케줄된 시크릿" 에러로 막힌다.
# personal-test처럼 자주 destroy/apply를 반복하는 환경에서는 0으로 둬서 즉시 완전
# 삭제되게 한다 (실제 develop/prod에서는 실수 삭제 방지를 위해 기본값 유지 권장).
variable "secret_recovery_window_in_days" {
  type        = number
  description = "DB Secret 삭제 시 복구 대기 기간(일). 0이면 즉시 완전 삭제(복구 불가)"
  default     = 7
}
