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

# Karpenter가 서브넷을 찾는 discovery 태그. BE·AI 노드는 WAS Private Subnet에만
# 배치되어야 하므로 이 서브넷에만 적용한다 (public/web/db에 붙으면 Karpenter가
# 아웃바운드 없는 DB 서브넷이나 설계상 금지된 public/web 서브넷에 노드를 만들 수 있음).
# aws_ec2_tag로 별도 관리하면 다른 apply에 이 리소스가 포함될 때마다 지워지므로,
# 호출부에서 merge해서 Subnet 자신의 tags에 직접 포함시킨다.
variable "was_private_subnet_tags" {
  type        = map(string)
  description = "WAS Private Subnet에만 추가할 태그 (Karpenter discovery 등)"
  default     = {}
}
