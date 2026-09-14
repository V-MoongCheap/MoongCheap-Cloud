# 클러스터 생성 시 AWS가 자동으로 self-managed 버전을 이미 깔아놓은 상태라(bootstrap_self_managed_addons=true),
# 여기서 명시적으로 관리형 Addon으로 다시 생성하면 기존 설치와 충돌한다. resolve_conflicts_on_create =
# "OVERWRITE"로 기존 self-managed 설치를 덮어쓰고 Terraform이 버전을 관리하도록 넘겨받는다.

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.project}-${var.env}-vpc-cni"
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.project}-${var.env}-kube-proxy"
  }
}

# CoreDNS는 Pod로 떠야 하는 애드온이라 스케줄링될 노드가 있어야 정상(ACTIVE) 상태가 된다.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.fe,
    aws_eks_node_group.be,
    aws_eks_node_group.ai_cpu,
  ]

  tags = {
    Name = "${var.project}-${var.env}-coredns"
  }
}

# EBS CSI Driver — IRSA Role(ebs_csi_driver)을 여기서 실제로 연결
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.fe,
    aws_eks_node_group.be,
    aws_eks_node_group.ai_cpu,
  ]

  tags = {
    Name = "${var.project}-${var.env}-ebs-csi-driver"
  }
}
