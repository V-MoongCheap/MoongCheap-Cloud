# 쿠버네티스 버전은 고정한다(D-7). 미지정이면 AWS가 그 시점의 최신 버전으로 만들어
# Close/Open으로 재생성할 때마다 버전이 흔들리고 Karpenter/Add-on 호환 기준이 사라진다.
# Endpoint 접근은 팀 확정 전까지 Public+Private 둘 다 허용하는 임시값이다.
resource "aws_eks_cluster" "this" {
  name     = "${var.project}-${var.env}-eks"
  role_arn = var.cluster_role_arn
  version  = var.cluster_version

  # 기본값 EXTENDED는 표준 지원(약 14개월)이 끝나면 자동으로 확장 지원 요금
  # ($0.60/h ≈ 월 $438, 표준 대비 +$365)으로 넘어간다. STANDARD는 그 시점에 요금 대신
  # 다음 minor 버전으로 자동 업그레이드한다 — 이 프로젝트는 요금 방지가 우선.
  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # 명시하지 않으면 클러스터가 CONFIG_MAP 모드로 생성되는데, 그 모드에서는
  # access.tf의 aws_eks_access_entry(팀원 권한 부여)가 아예 동작하지 않는다.
  # Access Entry를 쓰려면 API 또는 API_AND_CONFIG_MAP 이어야 한다.
  #
  # bootstrap_cluster_creator_admin_permissions는 access_config 블록을 명시하는 순간
  # true로 자동 적용되지 않는다 (블록 없이 생성할 때만 AWS가 알아서 켜준다). 그래서 여기서
  # 명시적으로 켜지 않으면 terraform apply를 실행한 본인조차 클러스터 admin 권한이 없어서
  # kubectl이 "must be logged in to the server"로 거부당한다
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  tags = {
    Name = "${var.project}-${var.env}-eks"
  }
}
