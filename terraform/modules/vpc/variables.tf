variable "project" {
  type        = string
  description = "프로젝트 이름"
  default     = "moongcheap"
}

variable "env" {
  type        = string
  description = "환경 구분 (dev/prod)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR 블록"
  default     = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "사용할 가용 영역 목록"
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public Subnet CIDR 목록 (NAT Instance 배치용, 보통 1개)"
  default     = ["10.0.0.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private Subnet CIDR 목록 (EKS Node/Pod 배치용, AZ당 1개)"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
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
