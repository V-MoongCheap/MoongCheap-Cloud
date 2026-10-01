data "aws_caller_identity" "current" {}

# 클러스터 최초 생성자는 bootstrap_cluster_creator_admin_permissions(cluster.tf)로
# AWS가 자동으로 admin Access Entry를 만들어준다. cluster_admin_usernames에 그
# 사람 이름이 남아있으면 aws_eks_access_entry.team이 같은 principal_arn으로
# 중복 생성을 시도해 ResourceInUseException이 난다(D-17).
#
# "지금 apply하는 사람"을 동적으로 감지해서 빼면 안 된다 — 최초 생성자가 아닌
# 다른 팀원이 apply할 때마다 그 사람 본인의 Terraform 관리 access entry가 삭제돼
# kubectl 접근이 끊기는 걸 실제로 재현했다(develop에서 v-infra-jh가 아닌 사람이
# apply했을 때 jh 항목이 지워짐). var.cluster_creator_username으로 "누가 최초로
# 만들었는지"를 고정해서 그 사람만 항상 제외한다.
#
# bootstrap_cluster_creator_admin_permissions = false인 환경(신규 클러스터)은 이
# 특수 케이스 자체가 없으므로 아무도 제외하지 않고 목록 전원을 동일하게 관리한다.
locals {
  team_admins = var.bootstrap_cluster_creator_admin_permissions ? setsubtract(toset(var.cluster_admin_usernames), toset([var.cluster_creator_username])) : toset(var.cluster_admin_usernames)
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
