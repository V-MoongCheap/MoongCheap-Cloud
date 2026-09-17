data "aws_caller_identity" "current" {}

# apply를 실행한 본인은 bootstrap_cluster_creator_admin_permissions(cluster.tf)로
# AWS가 자동으로 admin Access Entry를 만들어준다. cluster_admin_usernames에 그
# 본인 이름이 남아있으면 aws_eks_access_entry.team이 같은 principal_arn으로
# 중복 생성을 시도해 ResourceInUseException이 난다(D-17). 누가 apply하든
# 본인만 자동으로 빠지도록 caller의 IAM User 이름을 목록에서 제외한다.
locals {
  caller_iam_user = try(regex("user/(.+)$", data.aws_caller_identity.current.arn)[0], "")
  team_admins     = setsubtract(toset(var.cluster_admin_usernames), toset([local.caller_iam_user]))
}

# 클라우드 인프라팀 인원에게 클러스터 admin 권한 부여 (apply한 본인은 위에서 자동 제외됨)
resource "aws_eks_access_entry" "team" {
  for_each      = local.team_admins
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${each.value}"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "team_admin" {
  for_each      = local.team_admins
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.team[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
