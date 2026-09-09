# Tunnel의 실제 라우팅 규칙(어떤 호스트를 클러스터 내부 어떤 Service로 보낼지)은
# 여기서 관리하지 않는다. config_src = "local"로 두면 그 설정은 cloudflared를
# 실행하는 쪽(Part2, k8s 매니페스트의 config.yml/ConfigMap)이 직접 담당한다.
# 이 모듈은 Tunnel 자체의 생성과, 도메인을 그 Tunnel로 연결하는 DNS 레코드만 다룬다.
data "cloudflare_zone" "this" {
  zone_id = var.zone_id
}

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.account_id
  name       = var.tunnel_name
  secret     = random_id.tunnel_secret.b64_std
  config_src = "local"
}

resource "cloudflare_record" "tunnel" {
  zone_id = var.zone_id
  name    = var.subdomain == "" ? "@" : var.subdomain
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
}
