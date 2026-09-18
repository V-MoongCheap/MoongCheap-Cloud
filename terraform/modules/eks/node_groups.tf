# 아키텍처 설계서_V2 4.2: BE·AI는 부하에 따른 자동 확장이 필요해 Karpenter가 대체하고,
# FE는 부하 변동이 크지 않아 Managed Node Group을 유지한다.
#
# node_role_arn에 필요한 정책이 다 붙어있어야 노드가 join 가능하므로, 호출부에서
# module.iam 전체에 대한 depends_on이 걸려 있어야 한다.
resource "aws_eks_node_group" "fe" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-${var.env}-fe-ng"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.web_subnet_ids
  instance_types  = [var.fe_instance_type]

  # 네이밍 규약_V2 3.3 / 설계서_V2 4.2: gitops의 nodeSelector(workload: frontend)가
  # 이 Label을 기준으로 스케줄링한다. Helm values는 이미 이 값을 참조하고 있어(feat/gitops
  # 브랜치 확인), Node Group이 Label을 안 붙이면 FE Pod가 전부 Pending에 걸린다.
  labels = {
    workload = "frontend"
  }

  launch_template {
    id      = aws_launch_template.fe.id
    version = aws_launch_template.fe.latest_version
  }

  scaling_config {
    desired_size = var.fe_desired_size
    min_size     = var.fe_min_size
    max_size     = var.fe_max_size
  }

  tags = {
    Name = "${var.project}-${var.env}-fe-ng"
  }
}

# DEC-1 (a): ArgoCD·Karpenter Controller·Jenkins Controller처럼 계속 떠있어야 하는
# 시스템 워크로드 전용 고정 노드. Karpenter가 관리하는 BE·AI 노드는 사용률에 따라
# 통합/교체(consolidate)되므로 이런 상시 워크로드를 두기엔 부적합해 FE와 별개로 둔다.
resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-${var.env}-system-ng"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.was_subnet_ids
  instance_types  = [var.system_instance_type]

  labels = {
    workload = "system"
  }

  launch_template {
    id      = aws_launch_template.system.id
    version = aws_launch_template.system.latest_version
  }

  scaling_config {
    desired_size = var.system_desired_size
    min_size     = var.system_min_size
    max_size     = var.system_max_size
  }

  tags = {
    Name = "${var.project}-${var.env}-system-ng"
  }
}
