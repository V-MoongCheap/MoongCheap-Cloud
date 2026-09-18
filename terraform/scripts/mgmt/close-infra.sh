#!/usr/bin/env bash
# AWS 개발 인프라 Close — Compute만 내린다. Stateful·상시 리소스(RDS, S3, ElastiCache,
# OpenSearch, EKS Control Plane, VPC, ECR, IAM, Secrets)는 건드리지 않는다.
#   1. AWS 인증 확인
#   2. Managed Node Group 전부 desired → 0 (system-ng, fe-ng. Karpenter 컨트롤러도 여기서 내려간다)
#   3. BE·AI Karpenter 노드 EC2 종료 (컨트롤러가 죽은 뒤라 재프로비저닝 안 됨)
#   4. NAT Instance 중지 (노드가 다 내려간 뒤 마지막에)
#   5. 상태 확인 + 로그
# 수동 실행: /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/close-infra.sh
# 권한: 일반 사용자. sudo 불필요.
set -euo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
trap on_error ERR
trap on_exit EXIT

acquire_lock infra
info "시작: Close (cluster=${EKS_CLUSTER_NAME}, region=${AWS_REGION})"

require_vars EKS_CLUSTER_NAME NAT_INSTANCE_NAME_TAG
check_aws_auth

info "[1/4] Managed Node Group 축소 → 0 (${MANAGED_NODEGROUPS[*]})"
scale_managed_nodegroups close

info "[2/4] Karpenter(BE·AI) 노드 종료"
terminate_karpenter_nodes

info "[3/4] NAT Instance 중지"
stop_nat

info "[4/4] 최종 상태"
read -r nat_id nat_state < <(nat_instance)
info "  NAT ${nat_id}: ${nat_state}"
for entry in "${MANAGED_NODEGROUPS[@]}"; do
  info "  $(nodegroup_summary "${entry%%=*}")"
done
info "  Karpenter 노드: $(karpenter_instance_ids | wc -l)대"
info "  유지: EKS Control Plane, RDS, ElastiCache, OpenSearch, S3, ECR, VPC, IAM, Secrets"
