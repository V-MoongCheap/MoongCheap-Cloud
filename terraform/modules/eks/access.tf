data "aws_caller_identity" "current" {}

# 클라우드 인프라팀 인원에게 클러스터 admin 권한 부여
# (클러스터를 apply한 본인은 AWS가 자동으로 admin 접근 항목을 만들어주므로 var.cluster_admin_usernames에서 제외할 것)
resource "aws_eks_access_entry" "team" {
  for_each      = toset(var.cluster_admin_usernames)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${each.value}"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "team_admin" {
  for_each      = toset(var.cluster_admin_usernames)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.team[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
