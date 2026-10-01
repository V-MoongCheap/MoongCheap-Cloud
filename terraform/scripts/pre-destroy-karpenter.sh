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

echo "▶ ${CLUSTER_NAME} 존재 여부 확인..."
describe_err="$(aws eks describe-cluster --profile "$PROFILE" --region "$REGION" \
  --name "$CLUSTER_NAME" 2>&1 >/dev/null)" && describe_status=0 || describe_status=$?

if [ "$describe_status" -ne 0 ]; then
  if echo "$describe_err" | grep -q "ResourceNotFoundException"; then
    echo "  클러스터가 실제로 존재하지 않음 — Karpenter 정리 단계 스킵하고 종료."
    exit 0
  fi
  echo "⚠ 클러스터 조회 실패 (프로필/권한/네트워크 오류일 수 있음). 정리 여부를 확인할 수 없어 중단합니다."
  echo "$describe_err"
  exit 1
fi

echo "▶ ${CLUSTER_NAME} kubeconfig 연결..."
aws eks update-kubeconfig --profile "$PROFILE" --region "$REGION" \
  --name "$CLUSTER_NAME" --alias "$CTX"

if ! kubectl --context "$CTX" get crd nodepools.karpenter.sh >/dev/null 2>&1; then
  echo "  NodePool CRD 없음(Karpenter 미설치) — 정리할 것 없음."
  exit 0
fi

if ! kubectl --context "$CTX" get nodepool >/dev/null 2>&1; then
  echo "⚠ NodePool CRD는 있지만 조회 실패 (인증/권한/API 오류일 수 있음). 중단합니다."
  exit 1
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

# kubernetes.io/cluster/<클러스터>=owned는 Karpenter가 생성하는 모든 인스턴스에
# 자동으로 붙이는 태그(modules/karpenter IAM 정책의 RequestTag 조건으로도 강제됨).
# develop/prod가 같은 AWS 계정을 공유하므로 이 클러스터 태그로 걸러야 다른
# 클러스터의 정상 노드를 잔존물로 오인하지 않는다.
echo "▶ AWS 쪽에 ${CLUSTER_NAME} 소유 EC2가 실제로 남아있는지 최종 확인..."
leftover="$(aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
  --filters "Name=tag-key,Values=karpenter.sh/nodepool" \
            "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
            "Name=instance-state-name,Values=pending,running" \
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
