output "vpc_id" {
  value       = aws_vpc.this.id
  description = "생성된 VPC ID"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Public Subnet ID 목록"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "Private Subnet ID 목록 (EKS Node Group에서 사용)"
}

output "nat_instance_id" {
  value       = aws_instance.nat.id
  description = "NAT Instance ID"
}

output "nat_security_group_id" {
  value       = aws_security_group.nat.id
  description = "NAT Instance 보안 그룹 ID"
}
