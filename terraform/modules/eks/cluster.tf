# 쿠버네티스 버전은 미지정 — AWS가 그 시점의 기본(권장) 버전으로 생성한다.
# Endpoint 접근은 팀 확정 전까지 Public+Private 둘 다 허용하는 임시값이다.
resource "aws_eks_cluster" "this" {
  name     = "${var.project}-${var.env}-eks"
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # 명시하지 않으면 클러스터가 CONFIG_MAP 모드로 생성되는데, 그 모드에서는
  # access.tf의 aws_eks_access_entry(팀원 권한 부여)가 아예 동작하지 않는다.
  # Access Entry를 쓰려면 API 또는 API_AND_CONFIG_MAP 이어야 한다.
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags = {
    Name = "${var.project}-${var.env}-eks"
  }
}
