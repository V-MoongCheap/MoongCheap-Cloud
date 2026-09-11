variable "project" {
  type        = string
  description = "프로젝트 이름"
  default     = "moongcheap"
}

variable "env" {
  type        = string
  description = "환경 구분 (develop/prod)"
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

variable "web_private_subnet_cidrs" {
  type        = list(string)
  description = "WEB Private Subnet CIDR 목록 (FE Worker Node Group 배치용, AZ당 1개)"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "was_private_subnet_cidrs" {
  type        = list(string)
  description = "WAS Private Subnet CIDR 목록 (BE·AI Worker Node Group 배치용, AZ당 1개)"
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_private_subnet_cidrs" {
  type        = list(string)
  description = "DB Private Subnet CIDR 목록 (RDS 배치용, AZ당 1개, 인터넷 아웃바운드 라우트 없음)"
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}
