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
