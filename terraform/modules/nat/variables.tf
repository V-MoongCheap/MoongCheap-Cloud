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
  description = "NAT Security Group을 생성할 VPC ID (modules/vpc 출력값)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR 블록 (NAT SG 인바운드 허용 범위, MASQUERADE 대상 범위)"
}

variable "public_subnet_id" {
  type        = string
  description = "NAT Instance ENI를 배치할 Public Subnet ID (modules/vpc 출력값)"
}

variable "public_subnet_cidr" {
  type        = string
  description = "위 Public Subnet의 CIDR 블록 (ENI 고정 사설 IP 계산용)"
}

variable "nat_instance_type" {
  type        = string
  description = "NAT Instance 인스턴스 타입"
  default     = "t3a.micro"
}

variable "nat_enable_ssm" {
  type        = bool
  description = "NAT Instance에 SSM Session Manager 접속용 IAM Role을 붙일지 여부 (디버깅용, 기본 false)"
  default     = false
}
