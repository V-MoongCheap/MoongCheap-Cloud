data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Karpenter 컨트롤러(Helm Chart, GitOps에서 ArgoCD로 설치)가 쓰는 IRSA Role.
# 신뢰 정책의 서비스 어카운트 이름은 GitOps 쪽 Helm values의 serviceAccount 설정과
# 반드시 일치해야 한다 (modules/eks/irsa.tf의 EBS CSI Driver 패턴과 동일).
data "aws_iam_policy_document" "controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.karpenter_namespace}:${var.karpenter_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = "${var.project}-${var.env}-karpenter-controller-role"
  assume_role_policy = data.aws_iam_policy_document.controller_assume_role.json

  tags = {
    Name = "${var.project}-${var.env}-karpenter-controller-role"
  }
}

# AWS 공식 Karpenter Controller Policy를 이 프로젝트 계정/리전/클러스터에 맞게 축약 적용.
# iam:PassRole은 아래에서 만드는 노드용 Instance Profile의 Role로만 범위를 좁힌다.
data "aws_iam_policy_document" "controller" {
  statement {
    sid    = "AllowScopedEC2InstanceActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowScopedEC2InstanceTermination"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEC2Read"
    effect = "Allow"
    actions = [
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeInstances",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeImages",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPricingRead"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowSSMReadForAMI"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/*"]
  }

  statement {
    sid       = "AllowEKSClusterRead"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"]
  }

  # Karpenter가 노드를 만들 때 이 Role을 EC2에 넘겨줄 수 있어야 한다.
  # 아래에서 새로 만드는 전용 노드 Role로만 범위를 좁힌다.
  statement {
    sid       = "AllowPassNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]
  }

  # 기존 Instance Profile을 재사용할지 판단하려고 Karpenter가 목록을 조회한다.
  statement {
    sid       = "AllowListInstanceProfiles"
    effect    = "Allow"
    actions   = ["iam:ListInstanceProfiles"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "controller" {
  name   = "${var.project}-${var.env}-karpenter-controller-policy"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.controller.json
}

# Karpenter(BE·AI)가 만드는 노드 전용 Role — FE Managed Node Group Role과 별개로 만들고
# 아래 access_entry로 직접 등록한다 (Managed Node Group처럼 EKS가 자동으로 인증을 안 열어줌).
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project}-${var.env}-karpenter-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = {
    Name = "${var.project}-${var.env}-karpenter-node-role"
  }
}

# modules/iam/node_role.tf(FE Managed Node Group Role)와 동일한 정책 구성.
resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Managed Node Group이 아닌 EC2가 클러스터에 조인하려면 이 Access Entry가 반드시 있어야
# 한다 — 없으면 노드는 뜨지만 kubelet 인증이 안 돼 영원히 NotReady로 남는다.
# type=EC2_LINUX는 STANDARD와 달리 access_policy_association 없이도 노드 부트스트랩
# 권한이 자동으로 매핑된다.
resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
}

# Karpenter가 EC2NodeClass.spec.instanceProfile로 참조할 Instance Profile.
# Managed Node Group과 달리 EKS가 자동으로 만들어주지 않아 직접 만들어야 한다.
resource "aws_iam_instance_profile" "node" {
  name = "${var.project}-${var.env}-karpenter-node-profile"
  role = aws_iam_role.node.name

  tags = {
    Name = "${var.project}-${var.env}-karpenter-node-profile"
  }
}

# EC2NodeClass의 subnetSelectorTerms/securityGroupSelectorTerms가 찾을 태그.
# was_private Subnet과 be_ai SG는 modules/vpc의 var.tags, modules/eks의
# var.be_ai_security_group_tags로 이미 붙어있으니(호출부에서 merge) 여기선 안 붙인다.
# 클러스터 SG만 예외 — EKS가 자동 생성하는 리소스라 Terraform 소유 tags 블록이 없어서
# aws_ec2_tag로 붙일 수밖에 없다.
resource "aws_ec2_tag" "cluster_security_group_discovery" {
  resource_id = var.cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
