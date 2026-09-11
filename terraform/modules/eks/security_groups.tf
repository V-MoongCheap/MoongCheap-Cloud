# naming_convention_V2.md 3.2, 아키텍처 설계서_V2 3.3: RDS/Redis/OpenSearch 등에서
# CIDR 대신 Source Security Group 기반 접근 허용을 쓰려면 Node Group 전용 SG가 필요하다.
#
# 실제 apply로 확인된 치명적인 버그: Launch Template의 network_interfaces.security_groups에
# 커스텀 SG만 넣으면, EKS가 기본으로 붙여주는 Cluster Security Group이 "추가"가 아니라
# "대체"돼서 아예 안 붙는다. Cluster SG가 없으면 노드가 컨트롤 플레인과 통신을 못 해서
# 클러스터에 영원히 조인을 못 하고 Node Group이 CREATING에서 멈춘다 (실제 apply로 재현/확인함).
# 그래서 아래 Launch Template에는 커스텀 SG와 Cluster SG를 반드시 같이 넣는다.
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

  tags = {
    Name = "${var.project}-${var.env}-be-ai-sg"
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

resource "aws_launch_template" "be_ai" {
  name_prefix = "${var.project}-${var.env}-be-ai-lt-"

  network_interfaces {
    security_groups = [
      aws_security_group.be_ai.id,
      aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
    ]
  }

  metadata_options {
    http_tokens = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project}-${var.env}-be-ai-ng"
    }
  }
}
