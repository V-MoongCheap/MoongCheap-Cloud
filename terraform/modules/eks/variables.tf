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
  description = "클러스터를 배치할 Subnet ID 목록 (Private Subnet, modules/vpc 출력값)"
}

variable "node_role_arn" {
  type        = string
  description = "EKS Worker Node용 IAM Role ARN (modules/iam 출력값)"
}

variable "fe_instance_type" {
  type        = string
  description = "Frontend 전용 Node Group 인스턴스 타입"
  default     = "t3.large"
}

variable "be_instance_type" {
  type        = string
  description = "Backend 전용 Node Group 인스턴스 타입"
  default     = "t3.xlarge"
}

variable "ai_cpu_instance_type" {
  type        = string
  description = "AI CPU(API/Embedding/Cluster Matcher) 전용 Node Group 인스턴스 타입"
  default     = "m7i.large"
}

variable "cluster_admin_usernames" {
  type        = list(string)
  description = "클러스터 admin 권한을 받을 IAM 사용자 이름 목록"
  default     = ["v-infra-hs", "v-infra-jh", "v-infra-jw", "v-infra-ys"]
}

variable "node_desired_size" {
  type        = number
  description = "각 Node Group의 desired size (기본 1). 작은 인스턴스에서 Pod 여유 공간을 늘려 테스트할 때만 올린다."
  default     = 1
}
