#!/usr/bin/env bash
# Karpenter EC2는 Terraform state에 없어서 destroy가 못 지운다 — NodeClaim을 먼저
# 지워 Karpenter가 자기 노드를 정리하게 한 뒤, NodePool/EC2NodeClass를 정리한다.
# terraform destroy 전에 실행할 것.
# 사용법: ./pre-destroy-karpenter.sh <env> <aws-profile>
set -euo pipefail

ENV="${1:?사용법: $0 <env> <aws-profile>}"
PROFILE="${2:?사용법: $0 <env> <aws-profile>}"
REGION="ap-northeast-2"
CLUSTER_NAME="moongcheap-${ENV}-eks"
CTX="${ENV}-predestroy"

echo "▶ ${CLUSTER_NAME} kubeconfig 연결 시도..."
if ! aws eks update-kubeconfig --profile "$PROFILE" --region "$REGION" \
      --name "$CLUSTER_NAME" --alias "$CTX" 2>/dev/null; then
  echo "  클러스터가 이미 없거나 접근 불가 — Karpenter 정리 단계 스킵하고 종료."
  exit 0
fi

if ! kubectl --context "$CTX" get nodepool >/dev/null 2>&1; then
  echo "  NodePool CRD 없음(Karpenter 미설치) — 정리할 것 없음."
  exit 0
fi

NODEPOOLS="$(kubectl --context "$CTX" get nodepool -o name 2>/dev/null || true)"
if [ -z "$NODEPOOLS" ]; then
  echo "  NodePool 없음 — 정리할 것 없음."
  exit 0
fi

# NodePool을 먼저 지우면, Karpenter가 NodeClaim을 종료하려고 재조정(reconcile)할 때마다
# 그 NodePool을 참조하지 못해 "NodePool ... not found" 에러를 반복하며 영원히 못 끝난다
# 그래서 NodeClaim을 먼저 지워서 정상 종료시키고, NodePool은 맨 마지막에 지운다.
echo "▶ NodeClaim 삭제 (Karpenter가 자기 EC2를 graceful하게 정리하도록 유도)..."
kubectl --context "$CTX" delete nodeclaims --all --timeout=180s 2>/dev/null || true

echo "▶ NodeClaim이 실제로 다 사라질 때까지 대기 (최대 3분)..."
for i in $(seq 1 36); do
  remaining="$(kubectl --context "$CTX" get nodeclaims --no-headers 2>/dev/null | wc -l)"
  if [ "$remaining" -eq 0 ]; then
    echo "  모든 NodeClaim 정리 완료."
    break
  fi
  echo "  남은 NodeClaim: ${remaining}개 (${i}/36, 5초 후 재확인)"
  sleep 5
done

remaining="$(kubectl --context "$CTX" get nodeclaims --no-headers 2>/dev/null | wc -l)"
if [ "$remaining" -gt 0 ]; then
  echo "⚠ 3분이 지났는데도 NodeClaim ${remaining}개가 안 지워졌습니다."
  kubectl --context "$CTX" get nodeclaims -o wide
  echo "  terraform destroy 전에 위 NodeClaim/EC2를 직접 확인하세요."
  exit 1
fi

echo "▶ AWS 쪽에 karpenter.sh/nodepool 태그 붙은 EC2가 실제로 남아있는지 최종 확인..."
leftover="$(aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
  --filters "Name=tag-key,Values=karpenter.sh/nodepool" "Name=instance-state-name,Values=pending,running" \
  --query "Reservations[].Instances[].InstanceId" --output text)"

if [ -n "$leftover" ]; then
  echo "⚠ Karpenter 태그가 붙은 EC2가 아직 AWS에 남아있습니다: $leftover"
  echo "  terraform destroy 전에 확인 필요 (필요 시 aws ec2 terminate-instances로 직접 정리)."
  exit 1
fi

echo "▶ NodeClaim이 다 사라졌으니 이제 NodePool/EC2NodeClass 자체를 정리..."
kubectl --context "$CTX" delete nodepool --all --timeout=60s 2>/dev/null || true
kubectl --context "$CTX" delete ec2nodeclass --all --timeout=60s 2>/dev/null || true

echo "✅ Karpenter 노드 정리 완료. 이제 terraform destroy를 진행하면 됩니다."
