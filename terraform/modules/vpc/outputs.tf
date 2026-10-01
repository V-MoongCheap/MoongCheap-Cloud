output "vpc_id" {
  value       = aws_vpc.this.id
  description = "생성된 VPC ID"
}

output "vpc_cidr" {
  value       = aws_vpc.this.cidr_block
  description = "VPC CIDR 블록 (RDS Security Group 등에서 참조)"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Public Subnet ID 목록"
}

output "public_subnet_cidrs" {
  value       = var.public_subnet_cidrs
  description = "Public Subnet CIDR 목록 (modules/nat이 ENI 고정 IP 계산에 사용)"
}

output "web_private_subnet_ids" {
  value       = aws_subnet.web_private[*].id
  description = "WEB Private Subnet ID 목록 (FE Worker Node Group에서 사용)"
}

output "was_private_subnet_ids" {
  value       = aws_subnet.was_private[*].id
  description = "WAS Private Subnet ID 목록 (BE·AI Worker Node Group에서 사용)"
}

output "db_private_subnet_ids" {
  value       = aws_subnet.db_private[*].id
  description = "DB Private Subnet ID 목록 (RDS Subnet Group에서 사용)"
}

# NAT는 modules/nat로 분리되어 있어서, root에서 이 Route Table에 NAT행 aws_route를
# 추가로 붙일 수 있도록 ID를 내보낸다 (순환 의존 방지, main.tf 주석 참고).
output "web_private_route_table_id" {
  value       = aws_route_table.web_private.id
  description = "WEB Private Route Table ID (root에서 NAT행 aws_route 추가용)"
}

output "was_private_route_table_id" {
  value       = aws_route_table.was_private.id
  description = "WAS Private Route Table ID (root에서 NAT행 aws_route 추가용)"
}
