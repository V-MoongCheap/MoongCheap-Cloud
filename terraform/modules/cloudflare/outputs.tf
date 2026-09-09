output "tunnel_id" {
  description = "생성된 Cloudflare Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "tunnel_token" {
  description = "cloudflared 실행용 토큰"
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.tunnel_token
  sensitive   = true
}

output "cname_target" {
  description = "DNS가 가리키는 대상"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
}

output "fqdn" {
  description = "이 Tunnel에 실제로 연결된 도메인 (서브도메인 포함)"
  value       = var.subdomain == "" ? data.cloudflare_zone.this.name : "${var.subdomain}.${data.cloudflare_zone.this.name}"
}
