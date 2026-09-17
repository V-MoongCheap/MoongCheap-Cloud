# EKS 클러스터의 OIDC 발급자를 IAM에 등록 — 이후 만들 모든 Pod-level(IRSA) Role의 전제조건
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.project}-${var.env}-eks-oidc"
  }
}

# EBS CSI Driver IRSA Role
# 신뢰 정책의 서비스 어카운트 이름(kube-system/ebs-csi-controller-sa)은
# AWS EBS CSI Driver의 기본(default) 서비스 어카운트 이름과 반드시 일치해야 한다.
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${var.project}-${var.env}-ebs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = {
    Name = "${var.project}-${var.env}-ebs-csi-driver-role"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# External Secrets Operator(ESO) IRSA Role (DEC-2 확정: Secrets Manager → Pod
# 전달은 ESO로 통일 — docs/cloud_infra_architecture_V2.md 7.1, C-6).
#
# 원래는 modules/iam에 워크로드 IRSA Role을 모아두는 안을 검토했으나, module.iam이
# module.eks의 cluster_role_arn/node_role_arn을 먼저 만들어줘야 하는 반대 방향
# 의존이 이미 있어서 거기에 OIDC 기반 Role을 추가하면 모듈 간 순환 참조가 생긴다
# (실제로 `terraform validate`에서 Cycle 에러로 확인됨). OIDC Provider를 이미 이
# 모듈이 소유하고 있으므로 EBS CSI Role과 같은 자리에 둔다.
#
# ESO는 ClusterSecretStore 하나로 모든 서비스의 ExternalSecret을 처리하므로
# 워크로드별로 Role을 쪼개지 않고 조회 전용 Role 하나를 공유한다.
data "aws_region" "current" {}

data "aws_iam_policy_document" "eso_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.eso_namespace}:${var.eso_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.project}-${var.env}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role.json

  tags = {
    Name = "${var.project}-${var.env}-eso-role"
  }
}

# 이 프로젝트가 만드는 Secret은 전부 moongcheap-{env}-* 이름 규약을 따르므로
# (naming_convention_V2.md 10절) 접두어 하나로 전체를 커버할 수 있다.
data "aws_iam_policy_document" "eso_secrets_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project}-${var.env}-*",
    ]
  }
}

resource "aws_iam_role_policy" "eso_secrets_read" {
  name   = "${var.project}-${var.env}-eso-secrets-read-policy"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_secrets_read.json
}
