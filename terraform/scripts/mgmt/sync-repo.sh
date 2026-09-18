#!/usr/bin/env bash
# MGMT 서버의 MoongCheap-Cloud 클론을 develop 최신으로 맞추고, schedule.csv가 바뀌면
# update-cron.sh를 실행한다. cron으로 주기 실행(예: */5 * * * *).
#   - fast-forward만 허용. 로컬 변경·분기가 있으면 덮어쓰지 않고 로그만 남기고 종료
#   - git reset --hard / checkout -f 등 강제 동기화는 하지 않는다
#   - crontab에 MoongCheap 관리 구간이 아직 없으면(첫 설치) update-cron.sh를 한 번 실행
# 수동 실행: /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/sync-repo.sh
# 권한: 일반 사용자(REPO_DIR 소유자). sudo 불필요.
set -euo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
trap on_error ERR
trap on_exit EXIT

acquire_lock sync-repo
info "시작: repo 동기화 (${REPO_DIR} @ ${REPO_BRANCH})"

check_git
require_cmd crontab
require_dir "${REPO_DIR}"
cd "${REPO_DIR}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "git 저장소가 아님: ${REPO_DIR}"

# cron에서 자격증명 프롬프트로 멈추지 않게(public repo라 인증 불필요)
export GIT_TERMINAL_PROMPT=0

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "${branch}" == "${REPO_BRANCH}" ]] \
  || die "현재 브랜치 '${branch}' ≠ '${REPO_BRANCH}' — 브랜치를 바꾸지 않고 종료. 수동으로 git checkout ${REPO_BRANCH} 후 재실행"

dirty="$(git status --porcelain)"
if [[ -n "${dirty}" ]]; then
  die "로컬 변경사항 있음 — 덮어쓰지 않고 종료. MGMT 서버에서는 파일을 직접 고치지 말고 PR로 반영할 것:"$'\n'"${dirty}"
fi

old="$(git rev-parse HEAD)"
git fetch --quiet origin "${REPO_BRANCH}" || die "git fetch 실패 (네트워크/원격 확인)"
remote="$(git rev-parse "origin/${REPO_BRANCH}")"

run_update_cron_if_needed() {
  local reason="$1"
  info "update-cron.sh 실행 (${reason})"
  "${SCRIPT_DIR}/update-cron.sh" || die "update-cron.sh 실패 — 위 로그 참고"
}

if [[ "${old}" == "${remote}" ]]; then
  info "이미 최신 (${old:0:7})"
  if ! crontab -l 2>/dev/null | grep -qFx "${CRON_MARKER_BEGIN}"; then
    run_update_cron_if_needed "crontab에 MoongCheap 관리 구간 없음 — 초기 등록"
  fi
  exit 0
fi

if ! git merge-base --is-ancestor "${old}" "${remote}"; then
  die "로컬(${old:0:7})이 origin/${REPO_BRANCH}(${remote:0:7})의 조상이 아님 — fast-forward 불가. 로컬 커밋이 있거나 원격 이력이 재작성됨. 수동 확인 필요"
fi

info "pull --ff-only: ${old:0:7} → ${remote:0:7}"
git pull --ff-only --quiet origin "${REPO_BRANCH}" || die "git pull --ff-only 실패"
new="$(git rev-parse HEAD)"
[[ "${new}" == "${remote}" ]] || die "pull 후 HEAD(${new:0:7}) ≠ origin(${remote:0:7})"

changed="$(git diff --name-only "${old}" "${new}" -- "terraform/scripts/mgmt/" || true)"
if [[ -z "${changed}" ]]; then
  info "scripts/mgmt 변경 없음 (다른 경로만 변경됨)"
  exit 0
fi

info "scripts/mgmt 변경 파일:"
printf '%s\n' "${changed}" | while IFS= read -r f; do info "  ${f}"; done

if printf '%s\n' "${changed}" | grep -q '\.sh$'; then
  warn "스크립트 변경됨 — 다음 cron 실행부터 새 버전으로 동작함"
fi

if printf '%s\n' "${changed}" | grep -qx 'terraform/scripts/mgmt/schedule.csv'; then
  run_update_cron_if_needed "schedule.csv 변경"
fi
