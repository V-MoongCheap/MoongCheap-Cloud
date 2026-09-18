#!/usr/bin/env bash
# AWS 개발 인프라 Open — 비작업 시간에 내려둔 Compute만 다시 올린다.
#   1. AWS 인증 확인
#   2. NAT Instance 시작 (노드가 ECR·API에 나가려면 NAT가 먼저 있어야 함)
#   3. Managed Node Group desired → common.sh의 목표값 (system-ng 2, fe-ng 2). 요청은 한 번에,
#      대기는 순서대로(system → fe)
#   4. BE·AI(Karpenter): 할 일 없음 — Pod 수요가 생기면 Karpenter가 띄운다
#   5. 각 리소스 상태 확인 + 로그
# 수동 실행: /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/open-infra.sh
# 권한: 일반 사용자. sudo 불필요.
set -euo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
trap on_error ERR
trap on_exit EXIT

acquire_lock infra   # open/close가 동시에 돌지 않게 같은 락을 쓴다
info "시작: Open (cluster=${EKS_CLUSTER_NAME}, region=${AWS_REGION})"

require_vars EKS_CLUSTER_NAME NAT_INSTANCE_NAME_TAG
check_aws_auth

info "[1/3] NAT Instance 시작"
start_nat

info "[2/3] Managed Node Group 확장 (${MANAGED_NODEGROUPS[*]})"
scale_managed_nodegroups open

info "[3/3] 최종 상태"
read -r nat_id nat_state < <(nat_instance)
info "  NAT ${nat_id}: ${nat_state}"
for entry in "${MANAGED_NODEGROUPS[@]}"; do
  info "  $(nodegroup_summary "${entry%%=*}")"
done
info "  Karpenter 노드(${KARPENTER_NODEPOOL_NAMES[*]}): $(karpenter_instance_ids | wc -l)대 (Pod 수요에 따라 Karpenter가 조정)"
