# 아키텍처 설계서_V2 4.2: Node Group은 FE / BE·AI 2개로 구성한다.
# System Workload(Jenkins/ArgoCD/Prometheus/Loki/Grafana/Alloy) 전용 Node Group은
# 초기에는 만들지 않고 BE·AI Worker에 함께 배치한다 (실측 후 필요 시 분리 검토).
#
# node_role_arn에 필요한 정책(Worker/CNI/ECR ReadOnly)이 다 붙어있어야 노드가 join 가능하므로,
# 이 모듈을 호출하는 쪽(envs/develop)에서 module.iam 전체에 대한 depends_on이 걸려 있어야 한다.
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

resource "aws_eks_node_group" "be_ai" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-${var.env}-be-ai-ng"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.was_subnet_ids
  instance_types  = [var.be_ai_instance_type]

  # 네이밍 규약_V2 3.3 / 설계서_V2 4.2: gitops의 nodeSelector(workload: backend-ai)가
  # 이 Label을 기준으로 스케줄링한다. 위 fe Node Group과 동일한 이유로 필요.
  labels = {
    workload = "backend-ai"
  }

  launch_template {
    id      = aws_launch_template.be_ai.id
    version = aws_launch_template.be_ai.latest_version
  }

  scaling_config {
    desired_size = var.be_ai_desired_size
    min_size     = var.be_ai_min_size
    max_size     = var.be_ai_max_size
  }

  tags = {
    Name = "${var.project}-${var.env}-be-ai-ng"
  }
}
