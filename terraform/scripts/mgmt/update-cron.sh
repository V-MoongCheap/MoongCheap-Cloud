#!/usr/bin/env bash
# schedule.csv → 현재 사용자 crontab의 MoongCheap 관리 구간만 갱신한다.
#   - Marker(# BEGIN/END MOONGCHEAP MANAGED CRON) 사이만 교체, 그 밖의 항목은 그대로 보존
#   - CSV 검증에 하나라도 실패하면 crontab을 건드리지 않고 종료
#   - 적용 전 기존 crontab을 ~/.moongcheap/crontab-backup/ 에 백업
#   - sync-repo.sh 자체의 cron(*/5 sync-repo.sh)은 이 구간 밖에 사람이 직접 등록한다
# 수동 실행: /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/update-cron.sh
# 권한: 일반 사용자(자기 crontab). sudo 불필요.
set -euo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
trap on_error ERR
trap on_exit EXIT

acquire_lock update-cron
info "시작: crontab 갱신 (schedule=${SCHEDULE_FILE})"
require_cmd crontab
require_file "${SCHEDULE_FILE}"

EXPECTED_HEADER="action,time,days,enabled,memo"

# ── days → cron day_of_week ──────────────────────────────────────────────
# 입력: mon-fri / sat,sun / fri-mon(주 넘김 허용) / daily → 출력: 콤마 구분 숫자(0=sun) 오름차순
day_index() {
  case "$1" in
    sun) echo 0 ;; mon) echo 1 ;; tue) echo 2 ;; wed) echo 3 ;;
    thu) echo 4 ;; fri) echo 5 ;; sat) echo 6 ;;
    *) return 1 ;;
  esac
}

days_to_cron() {
  local name="$1" value="$2"
  local -a selected=(0 0 0 0 0 0 0)
  local token a b i
  [[ -n "${value}" ]] || die "${name}: days 비어 있음"
  if [[ "${value}" == "daily" ]]; then
    echo "*"; return 0
  fi
  IFS=',' read -ra tokens <<< "${value}"
  for token in "${tokens[@]}"; do
    if [[ "${token}" =~ ^([a-z]{3})-([a-z]{3})$ ]]; then
      a="$(day_index "${BASH_REMATCH[1]}")" || die "${name}: 요일 이름 잘못됨 '${BASH_REMATCH[1]}' (mon~sun)"
      b="$(day_index "${BASH_REMATCH[2]}")" || die "${name}: 요일 이름 잘못됨 '${BASH_REMATCH[2]}' (mon~sun)"
      i="${a}"
      while :; do
        selected[i]=1
        [[ "${i}" == "${b}" ]] && break
        i=$(( (i + 1) % 7 ))
      done
    elif [[ "${token}" =~ ^[a-z]{3}$ ]]; then
      a="$(day_index "${token}")" || die "${name}: 요일 이름 잘못됨 '${token}' (mon~sun)"
      selected[a]=1
    else
      die "${name}: days 형식 잘못됨 '${token}' (예: mon-fri, sat,sun, daily)"
    fi
  done
  local out=""
  for i in 0 1 2 3 4 5 6; do
    [[ "${selected[i]}" == 1 ]] && out+="${out:+,}${i}"
  done
  [[ -n "${out}" ]] || die "${name}: 선택된 요일 없음"
  echo "${out}"
}

# ── CSV 파싱 ─────────────────────────────────────────────────────────────
trim() { local s="${1//$'\r'/}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "${s}"; }

declare -a CRON_LINES=()
lineno=0
header_seen=0
enabled_count=0
disabled_count=0
while IFS= read -r raw || [[ -n "${raw:-}" ]]; do
  lineno=$((lineno + 1))
  line="$(trim "${raw}")"
  [[ -z "${line}" || "${line}" == \#* ]] && continue

  if (( header_seen == 0 )); then
    header="$(printf '%s' "${line}" | tr -d ' ')"
    [[ "${header}" == "${EXPECTED_HEADER}" ]] \
      || die "line ${lineno}: 헤더 불일치. 기대 '${EXPECTED_HEADER}', 실제 '${header}'"
    header_seen=1
    continue
  fi

  IFS=',' read -r action time days enabled memo extra <<< "${line}"
  action="$(trim "${action}" | tr '[:upper:]' '[:lower:]')"
  time="$(trim "${time}")"
  days="$(trim "${days}" | tr '[:upper:]' '[:lower:]')"
  enabled="$(trim "${enabled}" | tr '[:upper:]' '[:lower:]')"
  memo="$(trim "${memo:-}")"
  extra="$(trim "${extra:-}")"

  [[ -z "${extra}" ]] || die "line ${lineno}: 필드가 5개를 넘음 — memo에 콤마를 쓴 듯 ('${extra}')"
  case "${action}" in
    open|close) ;;
    *) die "line ${lineno}: action은 open|close만 허용 ('${action}')" ;;
  esac
  [[ "${time}" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]] \
    || die "line ${lineno}: time은 HH:MM (00:00~23:59) 형식 ('${time}')"
  hour="$((10#${BASH_REMATCH[1]}))"
  minute="$((10#${BASH_REMATCH[2]}))"
  dow="$(days_to_cron "line ${lineno} days" "${days}")"
  case "${enabled}" in
    true)  ;;
    false) disabled_count=$((disabled_count + 1)); info "line ${lineno}: ${action} ${time} ${days} — enabled=false, 건너뜀 (${memo})"; continue ;;
    *) die "line ${lineno}: enabled는 true|false만 허용 ('${enabled}')" ;;
  esac

  target="${SCRIPT_DIR}/${action}-infra.sh"
  [[ -x "${target}" ]] || die "line ${lineno}: 실행 파일 없음 또는 실행 권한 없음: ${target} (chmod +x 확인)"
  CRON_LINES+=("# ${action} ${time} ${days}${memo:+ — ${memo}}"$'\n'"${minute} ${hour} * * ${dow} ${target}")
  enabled_count=$((enabled_count + 1))
done < "${SCHEDULE_FILE}"

(( header_seen == 1 )) || die "CSV에 헤더 줄이 없음 (기대: ${EXPECTED_HEADER})"

info "CSV 검증 통과: 활성 ${enabled_count}건, 비활성 ${disabled_count}건"
(( enabled_count > 0 )) || warn "활성 스케줄이 0건 — Open/Close cron이 비게 됨(의도한 것인지 확인)"

# ── 기존 crontab 읽기·백업 ────────────────────────────────────────────────
current="$(crontab -l 2>/dev/null || true)"

begin_n="$(printf '%s\n' "${current}" | grep -c -Fx "${CRON_MARKER_BEGIN}" || true)"
end_n="$(printf '%s\n' "${current}" | grep -c -Fx "${CRON_MARKER_END}" || true)"
if (( begin_n != end_n || begin_n > 1 )); then
  die "crontab의 MoongCheap Marker가 손상됨(BEGIN=${begin_n}, END=${end_n}). 수동으로 정리 후 재실행: crontab -e"
fi

# ── 새 crontab 조립 ───────────────────────────────────────────────────────
# Marker 밖 내용만 남긴다(다른 사람이 등록한 항목 보존).
outside="$(printf '%s\n' "${current}" \
  | awk -v b="${CRON_MARKER_BEGIN}" -v e="${CRON_MARKER_END}" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip   { print }
    ')"

managed_block="${CRON_MARKER_BEGIN}
# generated by update-cron.sh from terraform/scripts/mgmt/schedule.csv ($(date --iso-8601=seconds))
# 직접 수정 금지 — schedule.csv를 고쳐 develop에 머지하면 sync-repo.sh가 반영한다
# 시각은 서버 timezone 기준(Asia/Seoul로 설정돼 있어야 함 — setup guide 참고)"
for line in ${CRON_LINES[@]+"${CRON_LINES[@]}"}; do
  managed_block+=$'\n'"${line}"
done
managed_block+=$'\n'"${CRON_MARKER_END}"

new_crontab="$(printf '%s\n' "${outside}" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
if [[ -n "${new_crontab}" ]]; then
  new_crontab+=$'\n\n'"${managed_block}"
else
  new_crontab="${managed_block}"
fi

# 타임스탬프 주석만 다른 경우는 변경으로 치지 않는다.
strip_ts() { grep -v '^# generated by update-cron.sh' || true; }
if [[ "$(printf '%s\n' "${current}" | strip_ts)" == "$(printf '%s\n' "${new_crontab}" | strip_ts)" ]]; then
  info "crontab 변경 없음 — 적용 생략"
  exit 0
fi

mkdir -p "${CRON_BACKUP_DIR}"
backup_file="${CRON_BACKUP_DIR}/crontab-$(date +%Y%m%d-%H%M%S)-$$.bak"
printf '%s\n' "${current}" > "${backup_file}"
info "기존 crontab 백업: ${backup_file}"

# crontab -는 문법 오류 시 기존 crontab을 건드리지 않고 실패한다.
printf '%s\n' "${new_crontab}" | crontab - || die "crontab 적용 실패 — 기존 crontab 유지됨. 백업: ${backup_file}"

info "crontab 적용 완료. MoongCheap 관리 구간:"
printf '%s\n' "${managed_block}" | while IFS= read -r l; do info "  ${l}"; done
