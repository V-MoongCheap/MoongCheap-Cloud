module "vpc" {
  source = "../../modules/vpc"

  env = "dev"
}

module "ecr" {
  source = "../../modules/ecr"
}

module "iam" {
  source = "../../modules/iam"

  env = "dev"
}

module "eks" {
  source = "../../modules/eks"

  env              = "dev"
  cluster_role_arn = module.iam.cluster_role_arn
  node_role_arn    = module.iam.node_role_arn
  subnet_ids       = module.vpc.private_subnet_ids

  # cluster_role_arn은 Role 생성 직후 알 수 있지만, 실제로는 정책(AmazonEKSClusterPolicy)이
  # 붙어있어야 클러스터 생성이 성공한다. output 값만으로는 이 순서가 보장되지 않아
  # module.iam 전체(정책 attachment 포함)가 끝난 뒤에 실행되도록 명시적으로 의존성을 건다.
  depends_on = [module.iam]
}
