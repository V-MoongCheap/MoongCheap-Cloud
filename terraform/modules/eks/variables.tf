variable "project" {
  type        = string
  description = "프로젝트 이름"
  default     = "moongcheap"
}

variable "env" {
  type        = string
  description = "환경 구분 (develop/prod)"
}

variable "cluster_role_arn" {
  type        = string
  description = "EKS 클러스터(컨트롤 플레인)용 IAM Role ARN (modules/iam 출력값)"
}

variable "subnet_ids" {
  type        = list(string)
  description = "클러스터 컨트롤 플레인이 사용할 Subnet ID 목록 (WEB+WAS Private Subnet 합집합, modules/vpc 출력값)"
}

variable "web_subnet_ids" {
  type        = list(string)
  description = "FE Worker Node Group을 배치할 WEB Private Subnet ID 목록 (아키텍처 설계서_V2 4.2)"
}

variable "was_subnet_ids" {
  type        = list(string)
  description = "BE·AI Worker Node Group을 배치할 WAS Private Subnet ID 목록 (아키텍처 설계서_V2 4.2)"
}

variable "vpc_id" {
  type        = string
  description = "FE/BE·AI 전용 Security Group을 생성할 VPC ID (modules/vpc 출력값)"
}

variable "node_role_arn" {
  type        = string
  description = "EKS Worker Node용 IAM Role ARN (modules/iam 출력값)"
}

# 아키텍처 설계서_V2 4.2: FE는 t3.small, BE·AI(Backend/API/AI CPU/Jenkins/ArgoCD/Observability
# 전부 통합)는 t3.large. 별도의 AI CPU 전용 Node Group은 두지 않는다.
variable "fe_instance_type" {
  type        = string
  description = "FE Worker Node Group 인스턴스 타입"
  default     = "t3.small"
}

variable "be_ai_instance_type" {
  type        = string
  description = "BE·AI Worker Node Group 인스턴스 타입 (Backend/API/AI CPU/Jenkins/ArgoCD/Observability 통합 배치)"
  default     = "t3.large"
}

variable "cluster_admin_usernames" {
  type        = list(string)
  description = "클러스터 admin 권한을 받을 IAM 사용자 이름 목록"
  default     = ["v-infra-hs", "v-infra-jh", "v-infra-jw", "v-infra-ys"]
}

# 아키텍처 설계서_V2 4.2: FE Desired=2. Min/Max는 문서상 [확정 필요]로 남아있어
# 우선 최소 비용으로 안전하게 기본값을 잡고, 팀 확정 후 조정한다.
variable "fe_desired_size" {
  type        = number
  description = "FE Worker Node Group desired size"
  default     = 2
}

variable "fe_min_size" {
  type        = number
  description = "FE Worker Node Group min size"
  default     = 1
}

variable "fe_max_size" {
  type        = number
  description = "FE Worker Node Group max size"
  default     = 2
}

# 아키텍처 설계서_V2 4.2: BE·AI Max=4는 "현재 비용 산정 기준 상한"으로 문서에 명시된 값.
# Desired/Min은 [확정 필요] 상태라 우선 1로 시작한다.
variable "be_ai_desired_size" {
  type        = number
  description = "BE·AI Worker Node Group desired size"
  default     = 1
}

variable "be_ai_min_size" {
  type        = number
  description = "BE·AI Worker Node Group min size"
  default     = 1
}

variable "be_ai_max_size" {
  type        = number
  description = "BE·AI Worker Node Group max size (비용 산정 기준 상한)"
  default     = 4
}
