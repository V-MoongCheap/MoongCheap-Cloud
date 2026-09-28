# naming_convention_V2.md 3.2, 아키텍처 설계서_V2 3.3: RDS/Redis/OpenSearch 등에서
# CIDR 대신 Source Security Group 기반 접근 허용을 쓰려면 Node Group 전용 SG가 필요하다.
#
# Launch Template의 network_interfaces.security_groups에 커스텀 SG만 넣으면, EKS가
# 기본으로 붙여주는 Cluster Security Group이 "추가"가 아니라 "대체"돼서 안 붙는다.
# 없으면 노드가 컨트롤 플레인과 통신 못 해 영원히 조인 못 하므로, 아래 Launch Template엔
# 커스텀 SG와 Cluster SG를 반드시 같이 넣는다.
resource "aws_security_group" "fe" {
  name        = "${var.project}-${var.env}-fe-sg"
  description = "FE Worker Node Group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-fe-sg"
  }
}

resource "aws_security_group" "be_ai" {
  name        = "${var.project}-${var.env}-be-ai-sg"
  description = "BE-AI Worker Node Group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.be_ai_security_group_tags, {
    Name = "${var.project}-${var.env}-be-ai-sg"
  })
}

# be_ai용 Launch Template은 없다 — Karpenter가 EC2NodeClass로 직접 인스턴스를 만든다.
# 이 SG는 그대로 두고 Karpenter가 태그 기반 discovery로 찾아 쓴다 (RDS/ElastiCache/
# OpenSearch가 이미 이 SG를 Source SG로 참조 중이라 새로 만들지 않는다).

resource "aws_security_group" "system" {
  name        = "${var.project}-${var.env}-system-sg"
  description = "System Worker Node Group (ArgoCD/Karpenter Controller/Jenkins Controller)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-system-sg"
  }
}

resource "aws_launch_template" "fe" {
  name_prefix = "${var.project}-${var.env}-fe-lt-"

  network_interfaces {
    security_groups = [
      aws_security_group.fe.id,
      aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
    ]
  }

  # IMDSv2 강제: http_tokens를 지정하지 않으면 IMDSv1도 허용되어, 노드 내
  # Pod가 IMDS 엔드포인트로 노드 IAM 역할 자격증명을 탈취할 수 있다.
  metadata_options {
    http_tokens = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project}-${var.env}-fe-ng"
    }
  }
}

resource "aws_launch_template" "system" {
  name_prefix = "${var.project}-${var.env}-system-lt-"

  network_interfaces {
    security_groups = [
      aws_security_group.system.id,
      aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
    ]
  }

  metadata_options {
    http_tokens = "required"
  }

  # D-59: vpc-cni의 ENABLE_PREFIX_DELEGATION만 켜면 IP는 늘어나지만 kubelet의 max-pods는
  # 그대로다. EKS가 Launch Template에 AMI를 지정하지 않은 노드 그룹의 max-pods를 자동
  # 계산할 때 Prefix Delegation을 고려하지 않기 때문에(계산식이 ENI x IP 기준), 여기서
  # 명시적으로 올려줘야 17 -> 110이 된다. 둘 중 하나만 하면 효과가 없다.
  #
  # AMI를 지정하지 않았으므로 EKS가 자체 NodeConfig를 뒤에 덧붙이고, 같은 키는 병합된다
  # (AL2023 / nodeadm). 그래서 여기엔 maxPods 한 줄만 둔다 — 클러스터 엔드포인트/CA/이름
  # 같은 값은 EKS가 채운다.
  user_data = base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="//"

    --//
    Content-Type: application/node.eks.aws

    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          maxPods: ${var.system_max_pods}

    --//--
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project}-${var.env}-system-ng"
    }
  }
}
