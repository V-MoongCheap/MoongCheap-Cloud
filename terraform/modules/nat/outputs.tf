output "network_interface_id" {
  value       = aws_network_interface.nat.id
  description = "NAT Instance의 독립 ENI ID (Private Subnet Route Table에서 참조)"
}

output "instance_id" {
  value       = aws_instance.nat.id
  description = "NAT Instance ID"
}

output "security_group_id" {
  value       = aws_security_group.nat.id
  description = "NAT Instance 보안 그룹 ID"
}

output "eip" {
  value       = aws_eip.nat.public_ip
  description = "NAT Instance에 연결된 Elastic IP"
}
