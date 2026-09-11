module "vpc" {
  source = "../../modules/vpc"

  env = "develop"
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

  # cluster_role_arn은 Role 생성 직후 알 수 있지만, 실제로는 정책(AmazonEKSClusterPolicy)이
  # 붙어있어야 클러스터 생성이 성공한다. output 값만으로는 이 순서가 보장되지 않아
  # module.iam 전체(정책 attachment 포함)가 끝난 뒤에 실행되도록 명시적으로 의존성을 건다.
  depends_on = [module.iam]
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

module "discord_secret" {
  source    = "../../modules/secrets"
  secret_id = "moongcheap-develop-infra-discord-secret"
}

module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  subdomain  = var.cloudflare_subdomain
}

module "budget_alert" {
  source = "../../modules/budget-alert"

  discord_webhook_url = module.discord_secret.secret_string
}
