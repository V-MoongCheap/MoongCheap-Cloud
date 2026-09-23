# 클러스터 생성 시 AWS가 자동으로 self-managed 버전을 이미 깔아놓은 상태라(bootstrap_self_managed_addons=true),
# 여기서 명시적으로 관리형 Addon으로 다시 생성하면 기존 설치와 충돌한다. resolve_conflicts_on_create =
# "OVERWRITE"로 기존 self-managed 설치를 덮어쓰고 Terraform이 버전을 관리하도록 넘겨받는다.

# D-59: t3.medium의 기본 max-pods는 ENI 3 x (ENI당 IP 6 - 1) + 2 = 17이고, system 노드가
# 이 한도에 먼저 부딪혀 alloy DaemonSet과 Prometheus가 Pending에 걸렸다(09-22, 09-23 재발).
# Prefix Delegation은 ENI의 IP 슬롯마다 IP 1개 대신 /28 프리픽스(IP 16개)를 붙여 한도를
# 110(EKS AMI가 vCPU 32 미만 인스턴스에 두는 상한)까지 끌어올린다. 노드 대수를 늘려도
# DaemonSet 슬롯이 같이 늘어 근본 해결이 안 되므로 한도 자체를 올린다.
#
# WARM_PREFIX_TARGET = 1: 여분 프리픽스를 1개만 미리 잡는다. WAS Private Subnet이 AZ당
# /24(251개)뿐이라 넉넉히 선할당하면 서브넷 IP가 먼저 마른다.
#
# 주의: 이 설정은 새로 뜨는 노드에만 적용된다. 기존 노드의 max-pods는 부팅 시 kubelet에
# 박히므로 노드를 교체해야 바뀐다 — Close(desired 0) 상태에서 apply하고 다음 Open에
# 새 노드로 반영하는 것이 무중단 경로다.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })

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
    aws_eks_node_group.system,
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
    aws_eks_node_group.system,
  ]

  tags = {
    Name = "${var.project}-${var.env}-ebs-csi-driver"
  }
}

# 아키텍처 설계서_V2 4.1: HPA 및 Pod/Node Resource Metric 수집용 필수 Add-on.
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.fe,
    aws_eks_node_group.system,
  ]

  tags = {
    Name = "${var.project}-${var.env}-metrics-server"
  }
}
