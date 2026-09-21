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
  name               = "${var.project}-${var.env}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = {
    Name = "${var.project}-${var.env}-ebs-csi-role"
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

# ── Workload IRSA (C-5 / 체크리스트 J-2a) ─────────────────────────────────
# 앱/Jenkins Pod가 AWS API를 직접 호출할 때 쓰는 Role. ESO Role(위)이 "Secret을
# 읽어 Pod에 넣는" 것이라면, 이쪽은 "Pod가 ECR/S3를 직접 쓰는" 권한이라 별개다.
# 전부 같은 OIDC Provider를 신뢰하고 SA 이름으로 주체를 고정한다(네이밍 3.4/5.4).

# Jenkins — kaniko ECR push. GetAuthorizationToken은 리소스 단위로 못 줄여서 "*",
# 나머지 push/pull 액션은 이 프로젝트 리포지토리(moongcheap/*)로 한정한다.
data "aws_iam_policy_document" "jenkins_assume_role" {
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
      values   = ["system:serviceaccount:${var.jenkins_namespace}:${var.jenkins_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  name               = "${var.project}-${var.env}-jenkins-role"
  assume_role_policy = data.aws_iam_policy_document.jenkins_assume_role.json

  tags = {
    Name = "${var.project}-${var.env}-jenkins-role"
  }
}

data "aws_iam_policy_document" "jenkins_ecr" {
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPullProjectRepos"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${var.project}/*",
    ]
  }
}

resource "aws_iam_role_policy" "jenkins_ecr" {
  name   = "${var.project}-${var.env}-jenkins-ecr-policy"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.jenkins_ecr.json
}

# BE — S3 Object 버킷 읽기/쓰기. 버킷 ARN을 안 넘기면(빈 문자열) 만들지 않는다
# (설계서 6.3 "접근 주체 [확정 필요]" 상태를 코드로 강제하지 않기 위함).
locals {
  be_namespace   = "${var.project}-${var.env}"
  create_be_role = var.be_s3_bucket_arn != ""
}

data "aws_iam_policy_document" "be_assume_role" {
  count = local.create_be_role ? 1 : 0

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
      values   = ["system:serviceaccount:${local.be_namespace}:${var.be_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "be" {
  count = local.create_be_role ? 1 : 0

  name               = "${var.project}-${var.env}-be-role"
  assume_role_policy = data.aws_iam_policy_document.be_assume_role[0].json

  tags = {
    Name = "${var.project}-${var.env}-be-role"
  }
}

data "aws_iam_policy_document" "be_s3" {
  count = local.create_be_role ? 1 : 0

  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.be_s3_bucket_arn]
  }

  statement {
    sid    = "ObjectReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.be_s3_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "be_s3" {
  count = local.create_be_role ? 1 : 0

  name   = "${var.project}-${var.env}-be-s3-policy"
  role   = aws_iam_role.be[0].id
  policy = data.aws_iam_policy_document.be_s3[0].json
}

# AI Role(moongcheap-{env}-ai-role)은 설계서 6.3에서 S3 접근이 "[접근 필요 시]"라
# 줄 권한이 아직 없다. 권한 없는 Role은 의미가 없으므로 필요가 확정되면 BE와 같은
# 패턴으로 추가한다.
