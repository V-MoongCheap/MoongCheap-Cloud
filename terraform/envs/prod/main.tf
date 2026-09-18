module "vpc" {
  source = "../../modules/vpc"

  env = "prod"

  was_private_subnet_tags = {
    "karpenter.sh/discovery" = "moongcheap-prod-eks"
  }
}

module "nat" {
  source = "../../modules/nat"

  env                = "prod"
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

  env = "prod"
}

module "eks" {
  source = "../../modules/eks"

  env              = "prod"
  cluster_role_arn = module.iam.cluster_role_arn
  node_role_arn    = module.iam.node_role_arn

  # 컨트롤 플레인은 WEB+WAS Private Subnet 전부에 ENI를 둘 수 있어야 하므로 합집합을 전달한다.
  subnet_ids     = concat(module.vpc.web_private_subnet_ids, module.vpc.was_private_subnet_ids)
  web_subnet_ids = module.vpc.web_private_subnet_ids
  was_subnet_ids = module.vpc.was_private_subnet_ids
  vpc_id         = module.vpc.vpc_id

  be_ai_security_group_tags = {
    "karpenter.sh/discovery" = "moongcheap-prod-eks"
  }

  # cluster_role_arn은 Role 생성 직후 알 수 있지만, 실제로는 정책(AmazonEKSClusterPolicy)이
  # 붙어있어야 클러스터 생성이 성공한다. output 값만으로는 이 순서가 보장되지 않아
  # module.iam 전체(정책 attachment 포함)가 끝난 뒤에 실행되도록 명시적으로 의존성을 건다.
  depends_on = [module.iam]
}

module "karpenter" {
  source = "../../modules/karpenter"

  env                       = "prod"
  cluster_name              = module.eks.cluster_name
  oidc_provider_arn         = module.eks.oidc_provider_arn
  oidc_issuer_url           = module.eks.cluster_oidc_issuer_url
  cluster_security_group_id = module.eks.cluster_security_group_id
}

module "rds" {
  source = "../../modules/rds"

  env                     = "prod"
  vpc_id                  = module.vpc.vpc_id
  be_ai_security_group_id = module.eks.be_ai_security_group_id
  db_subnet_ids           = module.vpc.db_private_subnet_ids

  # 설계서_V2 6.6·Runbook 10장: Stateful Resource는 일반 destroy에서 보호한다.
  # deletion_protection은 모듈 기본값이 이미 true(develop도 동일)라 명시는 재확인용이고,
  # skip_final_snapshot만 모듈 기본값(true, 반복 테스트 편의)과 달리 prod에서 false로 오버라이드한다.
  skip_final_snapshot = false
  deletion_protection = true
}

module "s3" {
  source = "../../modules/s3"

  env = "prod"
}

module "elasticache" {
  source = "../../modules/elasticache"

  env                     = "prod"
  vpc_id                  = module.vpc.vpc_id
  be_ai_security_group_id = module.eks.be_ai_security_group_id
  subnet_ids              = module.vpc.db_private_subnet_ids
}

module "opensearch" {
  source = "../../modules/opensearch"

  env                     = "prod"
  vpc_id                  = module.vpc.vpc_id
  be_ai_security_group_id = module.eks.be_ai_security_group_id
  subnet_id               = module.vpc.db_private_subnet_ids[0]
}

module "cloudflare_secret" {
  source    = "../../modules/secrets"
  secret_id = "moongcheap-prod-infra-cloudflare-secret"
}

module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  subdomain  = var.cloudflare_subdomain

  # cloudflare 모듈은 env 변수가 없어 tunnel_name 기본값("moongcheap")이 develop과
  # 겹친다. develop/prod가 같은 Cloudflare 계정·Zone을 공유하는 이상 동시 운영 시
  # 리소스 이름이 충돌하므로, personal-test와 동일하게 prod도 명시적으로 구분한다.
  tunnel_name = "moongcheap-prod"
}
