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
  # RunInstances/CreateFleet은 image·security-group·subnet·launch-template도 함께
  # 참조하는데, 이 리소스들은 이번 호출로 새로 생성/태깅되는 대상이 아니라서(이미
  # 존재하는 리소스를 참조만 함) RequestTag 컨텍스트 자체가 없다. 여기에 RequestTag
  # 조건을 걸면 항상 거짓으로 평가되어 매번 거부된다
  # launch-template 자신을 "생성"하는 CreateLaunchTemplate 액션에는 태그 조건이
  # 그대로 필요하므로 아래 AllowScopedEC2InstanceActionsWithTags에 남겨둔다.
  statement {
    sid    = "AllowScopedEC2InstanceActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}::image/*",
      "arn:aws:ec2:${data.aws_region.current.name}::snapshot/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:security-group/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:subnet/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:launch-template/*",
    ]
  }

  # Karpenter는 이번 호출로 실제 생성/태깅되는 리소스(fleet/instance/volume/
  # network-interface, 그리고 CreateLaunchTemplate 자체가 만드는 launch-template)에는
  # 항상 kubernetes.io/cluster/<클러스터>=owned, karpenter.sh/nodepool 태그를 자동으로
  # 붙인다. RequestTag 조건으로 이 태그가 없는 생성 요청은 막아 다른 클러스터/용도로
  # 이 Role이 오용되지 않게 한다.
  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:fleet/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid     = "AllowScopedResourceCreationTagging"
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:fleet/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
  }

  # Karpenter는 노드를 launch한 "이후"에도 Name·karpenter.sh/nodeclaim 태그를 별도
  # CreateTags 호출로 덧붙인다. 이 호출은 ec2:CreateAction 컨텍스트가 없는 독립
  # 호출이라 위 AllowScopedResourceCreationTagging(RequestTag 기반)로는 못 걸러지고,
  # 라이브 테스트에서 실제 UnauthorizedOperation으로 확인됨. 이미 이 클러스터가
  # 소유(owned)한 인스턴스에 한해서만, 그것도 정해진 태그 키만 덧붙일 수 있게 한다.
  statement {
    sid       = "AllowScopedResourceTagging"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["karpenter.sh/nodeclaim", "Name"]
    }
  }

  # 종료/삭제는 이 클러스터가 소유(owned)한 리소스로만 범위를 좁혀, 계정 내
  # 다른 EC2/Launch Template을 이 Role이 건드릴 수 없게 한다.
  statement {
    sid    = "AllowScopedEC2InstanceTermination"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
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

  # EC2NodeClass 삭제 시 Karpenter의 종료 finalizer가 (이 프로젝트가 쓰지 않는)
  # spec.role 방식용 자동 생성 Instance Profile이 남아있는지 항상 먼저 확인한다.
  # 이 권한이 없으면 GetInstanceProfile이 AccessDenied로 실패해 finalizer가 절대
  # 안 끝나고 EC2NodeClass 삭제가 무한 대기에 빠진다 (라이브 테스트로 실제 확인됨).
  # 읽기 전용 조회이므로 실제 삭제 권한(DeleteInstanceProfile 등)까지는 주지 않는다.
  statement {
    sid       = "AllowGetInstanceProfile"
    effect    = "Allow"
    actions   = ["iam:GetInstanceProfile"]
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
