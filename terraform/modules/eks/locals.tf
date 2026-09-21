# D-30: "정책 attachment가 끝난 뒤 EKS 리소스를 만든다"는 순서를 module 단위 depends_on 없이
# 만드는 자리. 조건식이 attachment ID 목록을 *참조*하므로 Terraform 그래프에는 의존 간선이
# 생기지만, 결과값은 어느 분기든 Role ARN 그대로라 값은 오염되지 않는다.
#   - 목록 길이는 항상 알려진 값이라(리소스 개수 고정) 조건도 plan 시점에 확정된다.
#   - 따라서 iam 모듈이 바뀌어도 cluster/node_role_arn이 unknown이 되지 않는다.
#     (node_role_arn은 ForceNew — unknown이 되면 Node Group 재생성이 잡힌다.)
#   - data source(aws_caller_identity 등)는 이 locals를 참조하지 않으므로 지연되지 않는다.
locals {
  cluster_role_arn = length(var.cluster_role_policy_attachment_ids) >= 0 ? var.cluster_role_arn : var.cluster_role_arn
  node_role_arn    = length(var.node_role_policy_attachment_ids) >= 0 ? var.node_role_arn : var.node_role_arn
}
