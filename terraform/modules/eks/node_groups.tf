# 서비스별 전용 Node Group (FE/BE/AI CPU 분리)
# node_role_arn에 필요한 정책(Worker/CNI/ECR ReadOnly)이 다 붙어있어야 노드가 join 가능하므로,
# 이 모듈을 호출하는 쪽(envs/dev)에서 module.iam 전체에 대한 depends_on이 걸려 있어야 한다.
resource "aws_eks_node_group" "fe" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-${var.env}-fe-node"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.fe_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = 1
    max_size     = 2
  }

  tags = {
    Name = "${var.project}-${var.env}-fe-node"
  }
}

resource "aws_eks_node_group" "be" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-${var.env}-be-node"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.be_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = 1
    max_size     = 2
  }

  tags = {
    Name = "${var.project}-${var.env}-be-node"
  }
}

resource "aws_eks_node_group" "ai_cpu" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-${var.env}-ai-cpu-node"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.ai_cpu_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = 1
    max_size     = 2
  }

  tags = {
    Name = "${var.project}-${var.env}-ai-cpu-node"
  }
}
