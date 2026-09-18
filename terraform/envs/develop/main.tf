# outputs.tf의 aws_account_id 등에서 사용
data "aws_caller_identity" "current" {}

module "vpc" {
  source = "../../modules/vpc"

  env = "develop"

  was_private_subnet_tags = {
    "karpenter.sh/discovery" = "moongcheap-develop-eks"
  }
}

module "nat" {
  source = "../../modules/nat"

  env                = "develop"
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  public_subnet_id   = module.vpc.public_subnet_ids[0]
  public_subnet_cidr = module.vpc.public_subnet_cidrs[0]
}

# vpc/nat 모듈 간 순환 의존을 피하려고 Route Table은 vpc가, 그 안의 NAT행 기본
# 라우트는 두 모듈이 다 만들어진 뒤 root에서 붙인다 (modules/vpc/main.tf 주석 참고).
resource "aws_route" "web_private_nat" {
  route_table_id         = module.vpc.web_private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.nat.network_interface_id
}

resource "aws_route" "was_private_nat" {
  route_table_id         = module.vpc.was_private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.nat.network_interface_id
}

module "ecr" {
  source = "../../modules/ecr"
}

module "iam" {
  source = "../../modules/iam"

  env = "develop"
}

module "eks" {
  source = "../../modules/eks"

  env              = "develop"
  cluster_role_arn = module.iam.cluster_role_arn
  node_role_arn    = module.iam.node_role_arn

  # 컨트롤 플레인은 WEB+WAS Private Subnet 전부에 ENI를 둘 수 있어야 하므로 합집합을 전달한다.
  subnet_ids     = concat(module.vpc.web_private_subnet_ids, module.vpc.was_private_subnet_ids)
  web_subnet_ids = module.vpc.web_private_subnet_ids
  was_subnet_ids = module.vpc.was_private_subnet_ids
  vpc_id         = module.vpc.vpc_id

  # be_ai SG에 Karpenter discovery 태그 (modules/eks/variables.tf 참고).
  be_ai_security_group_tags = {
    "karpenter.sh/discovery" = "moongcheap-develop-eks"
  }

  # C-5: BE Pod(be-sa)가 S3 Object 버킷을 읽고 쓸 IRSA Role. 버킷 ARN을 넘기면 만들어진다.
  be_s3_bucket_arn = module.s3.bucket_arn

  # cluster_role_arn은 Role 생성 직후 알 수 있지만, 실제로는 정책(AmazonEKSClusterPolicy)이
  # 붙어있어야 클러스터 생성이 성공한다. output 값만으로는 이 순서가 보장되지 않아
  # module.iam 전체(정책 attachment 포함)가 끝난 뒤에 실행되도록 명시적으로 의존성을 건다.
  depends_on = [module.iam]
}

module "karpenter" {
  source = "../../modules/karpenter"

  env                       = "develop"
  cluster_name              = module.eks.cluster_name
  oidc_provider_arn         = module.eks.oidc_provider_arn
  oidc_issuer_url           = module.eks.cluster_oidc_issuer_url
  cluster_security_group_id = module.eks.cluster_security_group_id
}

module "rds" {
  source = "../../modules/rds"

  env                     = "develop"
  vpc_id                  = module.vpc.vpc_id
  be_ai_security_group_id = module.eks.be_ai_security_group_id
  db_subnet_ids           = module.vpc.db_private_subnet_ids
}

module "s3" {
  source = "../../modules/s3"

  env = "develop"
}

module "elasticache" {
  source = "../../modules/elasticache"

  env                     = "develop"
  vpc_id                  = module.vpc.vpc_id
  be_ai_security_group_id = module.eks.be_ai_security_group_id
  subnet_ids              = module.vpc.db_private_subnet_ids
}

module "opensearch" {
  source = "../../modules/opensearch"

  env                     = "develop"
  vpc_id                  = module.vpc.vpc_id
  be_ai_security_group_id = module.eks.be_ai_security_group_id
  subnet_id               = module.vpc.db_private_subnet_ids[0]
}

module "cloudflare_secret" {
  source    = "../../modules/secrets"
  secret_id = "moongcheap-develop-infra-cloudflare-secret"
}

module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  subdomain  = var.cloudflare_subdomain

  # C-12 / J-3: 서비스별 호스트. DEC-3(BE를 api. 호스트로 갈지 /api 경로로 갈지)과
  # 프로젝트 도메인(moongcheap.shop) 전환이 끝나면 주석 해제 — 그 전엔 레코드 1개만 유지.
  # 프로젝트 도메인 기준: subdomain = "" (apex = FE) + 아래 4개 → 총 5개, 전부 1단계라 Universal SSL 적용.
  # 지금(wodurl.shop, subdomain = "moongcheap") 상태에서 미리 켜려면 "api.moongcheap" 식으로
  # 써야 하고 2단계라 SSL이 안 덮인다 — 테스트 외엔 권장하지 않음.
  # extra_subdomains = ["api", "jenkins", "grafana", "argocd"]
}

# 원래 terraform/bootstrap에 있었으나, 그 디렉토리는 local state를 Git에 커밋하는
# 예외 대상이라 Discord Webhook URL이 평문으로 커밋되는 사고가 났다(2026-09-16,
# docs/2026-09-16-feature-status-and-review.md 참고). envs/develop은 S3 remote
# backend를 쓰므로 여기로 옮기면 state가 로컬/Git에 남지 않는다.
#
# 주의: budget-alert 모듈은 env 변수가 없어(계정 전체 예산이라 develop/prod에
# 안 속함) 이름이 고정돼 있다(moongcheap-budget-alert 등). 지금은 develop만
# 배포 중(naming_convention_V2.md 8.1)이라 문제가 없지만, 나중에 envs/prod를
# 실제로 apply하게 되면 여기 복사해서 넣지 말 것 — 이름 충돌이 난다. 그 시점엔
# 이 모듈을 두 env가 공유하는 별도 위치(예: 전용 remote backend를 쓰는
# terraform/envs/shared/)로 다시 옮기는 걸 검토해야 한다.
module "discord_secret" {
  source    = "../../modules/secrets"
  secret_id = "moongcheap-develop-infra-discord-secret"
}

module "budget_alert" {
  source = "../../modules/budget-alert"

  discord_webhook_url = module.discord_secret.secret_string
}
