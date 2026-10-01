#!/usr/bin/env bash
# schedule.csv 기준으로 "지금 있어야 할 상태"(open|close)를 계산해 실제 인프라를 그 상태로 맞춘다.
#   - 기대 상태 = 활성 행 중 현재 시각 직전에 가장 최근 발생한 이벤트의 action
#   - open이면 open-infra.sh, close면 close-infra.sh 실행(둘 다 idempotent라 이미 맞으면 무변경)
#   - 최근 8일 내 이벤트가 없으면(unknown) 아무 것도 하지 않는다
# 언제 쓰나:
#   - sync-repo.sh가 schedule.csv 변경 시 자동 호출 (옛/새 기대 상태가 다를 때만)
#   - MGMT 서버가 꺼져 있어 cron을 놓쳤을 때 사람이 수동 실행
#   - 수동 연장 운영(Runbook 7.1) 중에는 돌리지 말 것 — 스케줄 기준으로 되돌린다
# 사용법: ./reconcile.sh [--dry-run]
# 권한: 일반 사용자. sudo 불필요.
set -euo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
trap on_error ERR
trap on_exit EXIT

dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

info "시작: reconcile (schedule=${SCHEDULE_FILE}, now=$(date --iso-8601=minutes))"

expected="$(schedule_expected_state "${SCHEDULE_FILE}")" || die "schedule.csv 파싱 실패 — 위 로그 참고"
info "기대 상태: ${expected}"

case "${expected}" in
  open|close)
    if (( dry_run )); then
      info "dry-run — ${expected}-infra.sh 실행 안 함"
      exit 0
    fi
    info "${expected}-infra.sh 실행"
    "${SCRIPT_DIR}/${expected}-infra.sh"
    ;;
  unknown)
    warn "최근 8일 내 활성 이벤트 없음 — 아무 것도 하지 않음"
    ;;
  *) die "기대 상태 계산 결과가 이상함: '${expected}'" ;;
esac
