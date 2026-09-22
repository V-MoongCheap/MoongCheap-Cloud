#!/usr/bin/env bash
# MoongCheap MGMT(KT Cloud) Open/Close 자동화 공통 변수·함수.
# 단독 실행하지 않고 다른 스크립트에서 `source`한다.
#
# 권한: 전부 일반 사용자(cron 소유자)로 실행 가능. sudo가 필요한 건 최초 1회
#   LOG_FILE 생성·소유권 변경과 /opt/moongcheap 디렉토리 생성뿐이다
#   (V-MoongCheap/docs/2026-09-18-mgmt-server-setup-guide.md 참고).

# cron은 PATH가 /usr/bin:/bin 정도라 aws v2(/usr/local/bin)를 못 찾는다.
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# ── AWS ──────────────────────────────────────────────────────────────────
AWS_REGION="ap-northeast-2"
export AWS_DEFAULT_REGION="${AWS_REGION}"
export AWS_PROFILE="${AWS_PROFILE:-default}"
export AWS_PAGER=""

# ── Repository ───────────────────────────────────────────────────────────
REPO_DIR="${MOONGCHEAP_REPO_DIR:-/opt/moongcheap/MoongCheap-Cloud}"
REPO_BRANCH="develop"
SCRIPT_DIR="${REPO_DIR}/terraform/scripts/mgmt"
SCHEDULE_FILE="${SCRIPT_DIR}/schedule.csv"

# ── 대상 리소스 ──────────────────────────────────────────────────────────
PROJECT="moongcheap"
ENV="develop"
EKS_CLUSTER_NAME="${PROJECT}-${ENV}-eks"

# Open 시 desired로 올리고 Close 시 0으로 내리는 Managed Node Group 목록 ("이름=open시 desired").
# 순서 = Open 순서(컨트롤러가 뜨는 system부터). Close는 전부 0으로 내리므로 순서 무관.
# Close가 되려면 Terraform 쪽 min_size가 0이어야 한다(modules/eks fe_min_size / system_min_size).
#   - system-ng: ArgoCD·Karpenter 컨트롤러 등 고정 노드 (DEC-1, t3.medium ×3 — 2026-09-22
#     실측 결과 2대(34슬롯)로는 max-pods 한도(17/노드) 초과해 argocd-server·jenkins-0이
#     Pending이라 3대로 증설, BE·AI Subnet)
#   - fe-ng    : FE 워크로드 (t3.small ×2)
MANAGED_NODEGROUPS=(
  "${PROJECT}-${ENV}-system-ng=3"
  "${PROJECT}-${ENV}-fe-ng=2"
)

# BE·AI는 Karpenter 노드라 Node Group이 없다. Close 때는 아래 NodePool 태그를 가진 EC2를
# 직접 종료하고, Open 때는 Pod 수요에 따라 Karpenter가 다시 띄우므로 할 일이 없다.
# (Karpenter 컨트롤러가 system-ng 위에서 돌기 때문에 Managed Node Group을 전부 0으로 내린
#  뒤 종료해야 재프로비저닝이 안 된다 — close-infra.sh 순서 참고)
KARPENTER_NODEPOOL_TAG_KEY="karpenter.sh/nodepool"
KARPENTER_NODEPOOL_NAMES=("be-ai")

NAT_INSTANCE_NAME_TAG="${PROJECT}-${ENV}-nat"

# ── 운영 ─────────────────────────────────────────────────────────────────
LOG_FILE="${MOONGCHEAP_LOG_FILE:-/var/log/moongcheap-infra.log}"
LOCK_DIR="${TMPDIR:-/tmp}"
CRON_MARKER_BEGIN="# BEGIN MOONGCHEAP MANAGED CRON"
CRON_MARKER_END="# END MOONGCHEAP MANAGED CRON"
CRON_BACKUP_DIR="${HOME}/.moongcheap/crontab-backup"

WAIT_INTERVAL=15   # 초
WAIT_TIMEOUT=900   # 초 (노드 join/종료는 보통 3~5분)

SCRIPT_NAME="$(basename "${0:-common.sh}")"
_STARTED_AT="$(date +%s)"

# ── 로그 ─────────────────────────────────────────────────────────────────
# LOG_FILE에 못 쓰면(권한 미설정) stderr로만 남긴다 — cron 메일/저널에서라도 보이게.
_log_target_checked=0
log() {
  local level="$1"; shift
  local line
  line="$(date --iso-8601=seconds) [${SCRIPT_NAME}] [${level}] $*"
  if [[ -w "${LOG_FILE}" ]] || { [[ ! -e "${LOG_FILE}" ]] && [[ -w "$(dirname "${LOG_FILE}")" ]]; }; then
    printf '%s\n' "${line}" >> "${LOG_FILE}"
  elif [[ ${_log_target_checked} -eq 0 ]]; then
    _log_target_checked=1
    printf '%s\n' "$(date --iso-8601=seconds) [${SCRIPT_NAME}] [WARN] LOG_FILE(${LOG_FILE})에 쓸 수 없어 stderr로만 기록함 — setup guide의 로그 파일 생성 단계 확인" >&2
  fi
  printf '%s\n' "${line}" >&2
}
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
die()  { log ERROR "$@"; exit 1; }

# set -e로 실패한 지점을 로그에 남긴다. 각 스크립트에서 `trap on_error ERR` 로 건다.
on_error() {
  local rc=$? line="${BASH_LINENO[0]:-?}" cmd="${BASH_COMMAND:-?}"
  log ERROR "실패 (exit=${rc}) at ${BASH_SOURCE[1]:-?}:${line}: ${cmd}"
}

# 시작/종료·소요시간을 남긴다. 각 스크립트에서 `trap on_exit EXIT` 로 건다.
on_exit() {
  local rc=$?
  local elapsed=$(( $(date +%s) - _STARTED_AT ))
  if [[ ${rc} -eq 0 ]]; then
    info "종료: 성공 (소요 ${elapsed}s)"
  else
    log ERROR "종료: 실패 exit=${rc} (소요 ${elapsed}s)"
  fi
}

# ── 사전 점검 ────────────────────────────────────────────────────────────
require_cmd() {
  local c
  for c in "$@"; do
    command -v "${c}" >/dev/null 2>&1 || die "필수 명령 없음: ${c} (PATH=${PATH})"
  done
}
require_file() { [[ -f "$1" ]] || die "파일 없음: $1"; }
require_dir()  { [[ -d "$1" ]] || die "디렉토리 없음: $1"; }
require_vars() {
  local v
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || die "필수 변수 비어 있음: ${v}"
  done
}

check_aws_auth() {
  require_cmd aws
  local ident
  ident="$(aws sts get-caller-identity --query 'Arn' --output text 2>&1)" \
    || die "AWS 인증 실패 (profile=${AWS_PROFILE}, region=${AWS_REGION}): ${ident}"
  info "AWS 인증 OK: ${ident}"
}

check_git() { require_cmd git; }

# 같은 스크립트가 겹쳐 돌지 않게 한다(cron 지연·수동 실행 중복). 락 이름은 스크립트별.
acquire_lock() {
  local name="${1:-${SCRIPT_NAME%.sh}}"
  local lock_file="${LOCK_DIR}/moongcheap-${name}.lock"
  exec 9>"${lock_file}" || die "락 파일 생성 실패: ${lock_file}"
  flock -n 9 || die "이미 실행 중 (${lock_file}) — 중복 실행 건너뜀"
}

# ── 대기 ─────────────────────────────────────────────────────────────────
# wait_until "설명" <조건 함수 또는 명령...>  — 조건이 0을 반환할 때까지 WAIT_INTERVAL 간격으로 재시도
wait_until() {
  local desc="$1"; shift
  local deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
  while ! "$@"; do
    if (( $(date +%s) >= deadline )); then
      die "타임아웃(${WAIT_TIMEOUT}s): ${desc}"
    fi
    sleep "${WAIT_INTERVAL}"
  done
  info "확인: ${desc}"
}

# ── schedule.csv ─────────────────────────────────────────────────────────
# 형식: action,time,days,enabled,memo  ('#' 줄·빈 줄 무시, 첫 유효 줄이 헤더)
SCHEDULE_HEADER="action,time,days,enabled,memo"

trim() { local s="${1//$'\r'/}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "${s}"; }

day_index() {
  case "$1" in
    sun) echo 0 ;; mon) echo 1 ;; tue) echo 2 ;; wed) echo 3 ;;
    thu) echo 4 ;; fri) echo 5 ;; sat) echo 6 ;;
    *) return 1 ;;
  esac
}

# days_to_cron <에러표시용 이름> <값>
#   mon-fri / sat,sun / fri-mon(주 넘김 허용) / daily → cron day_of_week ("1,2,3,4,5" 또는 "*")
days_to_cron() {
  local name="$1" value="$2"
  local -a selected=(0 0 0 0 0 0 0)
  local token a b i
  [[ -n "${value}" ]] || die "${name}: days 비어 있음"
  if [[ "${value}" == "daily" ]]; then echo "*"; return 0; fi
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

# parse_schedule_file <csv>
#   검증하며 파싱. 한 줄이라도 잘못되면 die(호출자는 아무 것도 바꾸지 않은 상태).
#   출력(행마다, 탭 구분): action  minute  hour  dow_cron  enabled  time_raw  days_raw  memo
parse_schedule_file() {
  local file="$1"
  local raw line header lineno=0 header_seen=0
  local action time days enabled memo extra hour minute dow
  require_file "${file}"
  while IFS= read -r raw || [[ -n "${raw:-}" ]]; do
    lineno=$((lineno + 1))
    line="$(trim "${raw}")"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    if (( header_seen == 0 )); then
      header="$(printf '%s' "${line}" | tr -d ' ')"
      [[ "${header}" == "${SCHEDULE_HEADER}" ]] \
        || die "$(basename "${file}") line ${lineno}: 헤더 불일치. 기대 '${SCHEDULE_HEADER}', 실제 '${header}'"
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
      true|false) ;;
      *) die "line ${lineno}: enabled는 true|false만 허용 ('${enabled}')" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${action}" "${minute}" "${hour}" "${dow}" "${enabled}" "${time}" "${days}" "${memo}"
  done < "${file}"
  (( header_seen == 1 )) || die "$(basename "${file}")에 헤더 줄이 없음 (기대: ${SCHEDULE_HEADER})"
}

# schedule_expected_state <csv> [기준 epoch, 기본 now]
#   활성 행들 중 "기준 시각 이전에 가장 최근 발생한 이벤트"의 action을 출력한다(open|close).
#   최근 8일 안에 이벤트가 없으면 unknown. 같은 시각에 open·close가 겹치면 close.
#   파싱 실패 시 die — 호출자가 옛 CSV를 넘길 때는 `|| echo unknown`으로 감싼다.
schedule_expected_state() {
  local file="$1" now="${2:-$(date +%s)}"
  local rows best_ts=0 best_action="unknown"
  local action minute hour dow enabled _t _d _m
  local day_offset day_epoch day_dow day_date ts
  rows="$(parse_schedule_file "${file}")" || return 1
  while IFS=$'\t' read -r action minute hour dow enabled _t _d _m; do
    [[ "${enabled}" == "true" ]] || continue
    for day_offset in 0 1 2 3 4 5 6 7; do
      day_epoch=$(( now - day_offset * 86400 ))
      day_date="$(date -d "@${day_epoch}" +%F)"
      day_dow="$(date -d "@${day_epoch}" +%w)"
      if [[ "${dow}" != "*" ]] && ! [[ ",${dow}," == *",${day_dow},"* ]]; then continue; fi
      ts="$(date -d "${day_date} $(printf '%02d:%02d' "${hour}" "${minute}")" +%s)"
      (( ts <= now )) || continue
      if (( ts > best_ts )) || { (( ts == best_ts )) && [[ "${action}" == "close" ]]; }; then
        best_ts="${ts}"; best_action="${action}"
      fi
    done
  done <<< "${rows}"
  echo "${best_action}"
}

# ── EKS Managed Node Group ───────────────────────────────────────────────
# 출력: status desired min max (탭 구분). Node Group이 없으면 return 2, 그 외 실패 return 1.
nodegroup_info() {
  local out
  if out="$(aws eks describe-nodegroup --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "$1" \
      --query 'nodegroup.[status,scalingConfig.desiredSize,scalingConfig.minSize,scalingConfig.maxSize]' \
      --output text 2>&1)"; then
    printf '%s\n' "${out}"
    return 0
  fi
  [[ "${out}" == *ResourceNotFoundException* ]] && return 2
  printf '%s\n' "${out}" >&2
  return 1
}

# Node Group에 속한 EC2 중 pending/running 개수
nodegroup_running_count() {
  aws ec2 describe-instances \
    --filters "Name=tag:eks:cluster-name,Values=${EKS_CLUSTER_NAME}" \
              "Name=tag:eks:nodegroup-name,Values=$1" \
              "Name=instance-state-name,Values=pending,running" \
    --query 'length(Reservations[].Instances[])' --output text
}

_nodegroup_is_active() {
  local status
  status="$(nodegroup_info "$1" | cut -f1)"
  [[ "${status}" == "ACTIVE" ]]
}

_nodegroup_count_is() {
  [[ "$(nodegroup_running_count "$1")" == "$2" ]]
}

# request_nodegroup_scale <이름> <목표 desired>
#   API 호출만 하고 기다리지 않는다. 이미 목표값이면 호출 없이 통과(idempotent).
#   return 0 = 요청됨/이미 목표, 2 = Node Group 없음(건너뜀), 그 외 = die
request_nodegroup_scale() {
  local ng="$1" target="$2"
  local ng_info status desired min max rc
  ng_info="$(nodegroup_info "${ng}")" && rc=0 || rc=$?
  if (( rc == 2 )); then
    warn "${ng}: Node Group 없음 — 건너뜀 (아직 생성 전이거나 이름 확인 필요: common.sh MANAGED_NODEGROUPS)"
    return 2
  fi
  (( rc == 0 )) || die "${ng}: Node Group 조회 실패"
  IFS=$'\t' read -r status desired min max <<< "${ng_info}"

  if [[ "${status}" == "UPDATING" ]]; then
    warn "${ng}: 이전 업데이트 진행 중(UPDATING) — ACTIVE까지 대기"
    wait_until "${ng} ACTIVE" _nodegroup_is_active "${ng}"
    IFS=$'\t' read -r status desired min max < <(nodegroup_info "${ng}")
  fi
  [[ "${status}" == "ACTIVE" ]] || die "${ng}: 상태 ${status} — 스케일 불가"

  if (( target < min || target > max )); then
    die "${ng}: 목표 desired=${target}가 min=${min}~max=${max} 범위 밖. Terraform(modules/eks *_min_size/*_max_size)에서 범위를 먼저 조정할 것"
  fi

  if [[ "${desired}" == "${target}" ]]; then
    info "${ng}: desired 이미 ${target} — 변경 없음"
  else
    info "${ng}: desired ${desired} → ${target}"
    aws eks update-nodegroup-config --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${ng}" \
      --scaling-config "desiredSize=${target}" --query 'update.id' --output text >/dev/null \
      || die "${ng}: update-nodegroup-config 실패"
  fi
}

# wait_nodegroup_scaled <이름> <목표 desired>
wait_nodegroup_scaled() {
  local ng="$1" target="$2"
  wait_until "${ng} ACTIVE" _nodegroup_is_active "${ng}"
  wait_until "${ng} 실행 인스턴스 ${target}대" _nodegroup_count_is "${ng}" "${target}"
}

# scale_managed_nodegroups open|close
#   MANAGED_NODEGROUPS 전부에 요청을 먼저 다 보내고(병렬로 스케일되게) 그 다음 순서대로 기다린다.
scale_managed_nodegroups() {
  local mode="$1" entry ng desired target rc
  local -a pending=()
  for entry in "${MANAGED_NODEGROUPS[@]}"; do
    ng="${entry%%=*}"; desired="${entry##*=}"
    target="${desired}"; [[ "${mode}" == "close" ]] && target=0
    request_nodegroup_scale "${ng}" "${target}" && rc=0 || rc=$?
    (( rc == 2 )) && continue
    (( rc == 0 )) || exit "${rc}"
    pending+=("${ng}=${target}")
  done
  for entry in ${pending[@]+"${pending[@]}"}; do
    wait_nodegroup_scaled "${entry%%=*}" "${entry##*=}"
  done
}

# 상태 로그용 한 줄. Node Group이 없으면 "(없음)"
nodegroup_summary() {
  local ng="$1" ng_info rc status desired min max
  ng_info="$(nodegroup_info "${ng}")" && rc=0 || rc=$?
  if (( rc == 2 )); then echo "${ng}: (없음)"; return 0; fi
  (( rc == 0 )) || { echo "${ng}: 조회 실패"; return 0; }
  IFS=$'\t' read -r status desired min max <<< "${ng_info}"
  echo "${ng}: ${status} desired=${desired} (min=${min}, max=${max}) running=$(nodegroup_running_count "${ng}")"
}

# ── NAT Instance ─────────────────────────────────────────────────────────
# Name 태그로 찾는다(user_data 변경 시 인스턴스가 교체돼 ID가 바뀌므로 ID 하드코딩 금지).
# 출력: instance-id state
nat_instance() {
  local out
  out="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${NAT_INSTANCE_NAME_TAG}" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text)"
  local n
  n="$(printf '%s\n' "${out}" | sed '/^$/d' | wc -l)"
  (( n == 1 )) || die "NAT Instance(Name=${NAT_INSTANCE_NAME_TAG}) 조회 결과 ${n}건 — 1건이어야 함: ${out:-없음}"
  printf '%s\n' "${out}"
}

_instance_state() {
  aws ec2 describe-instances --instance-ids "$1" \
    --query 'Reservations[0].Instances[0].State.Name' --output text
}
_instance_state_is() { [[ "$(_instance_state "$1")" == "$2" ]]; }

start_nat() {
  local id state
  read -r id state < <(nat_instance) || true
  [[ -n "${id:-}" ]] || die "NAT Instance 조회 실패"
  case "${state}" in
    running) info "NAT ${id}: 이미 running — 변경 없음" ;;
    pending) info "NAT ${id}: 시작 중(pending) — running 대기" ;;
    stopping)
      warn "NAT ${id}: 중지 진행 중(stopping) — stopped 후 시작"
      wait_until "NAT ${id} stopped" _instance_state_is "${id}" stopped
      aws ec2 start-instances --instance-ids "${id}" >/dev/null || die "NAT start 실패"
      ;;
    stopped)
      info "NAT ${id}: start"
      aws ec2 start-instances --instance-ids "${id}" >/dev/null || die "NAT start 실패"
      ;;
    *) die "NAT ${id}: 예상 밖 상태 ${state}" ;;
  esac
  wait_until "NAT ${id} running" _instance_state_is "${id}" running
}

stop_nat() {
  local id state
  read -r id state < <(nat_instance) || true
  [[ -n "${id:-}" ]] || die "NAT Instance 조회 실패"
  case "${state}" in
    stopped)  info "NAT ${id}: 이미 stopped — 변경 없음" ;;
    stopping) info "NAT ${id}: 이미 중지 중 — stopped 대기" ;;
    running|pending)
      info "NAT ${id}: stop"
      aws ec2 stop-instances --instance-ids "${id}" >/dev/null || die "NAT stop 실패"
      ;;
    *) die "NAT ${id}: 예상 밖 상태 ${state}" ;;
  esac
  wait_until "NAT ${id} stopped" _instance_state_is "${id}" stopped
}

# ── Karpenter 노드 ───────────────────────────────────────────────────────
# 이 클러스터의 Karpenter NodePool 소속 EC2(pending/running) ID 목록. 없으면 빈 출력.
karpenter_instance_ids() {
  local pools
  pools="$(IFS=,; printf '%s' "${KARPENTER_NODEPOOL_NAMES[*]}")"
  aws ec2 describe-instances \
    --filters "Name=tag:kubernetes.io/cluster/${EKS_CLUSTER_NAME},Values=owned" \
              "Name=tag:${KARPENTER_NODEPOOL_TAG_KEY},Values=${pools}" \
              "Name=instance-state-name,Values=pending,running" \
    --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | sed '/^$/d'
}

_karpenter_all_gone() { [[ -z "$(karpenter_instance_ids)" ]]; }

# Karpenter 노드를 EC2 API로 직접 종료한다(kubectl 없이). drain 없이 꺼지므로 Pod는 즉시
# 죽는다 — 개발 환경 비작업 시간 전제. Karpenter 컨트롤러가 살아 있으면 Pending Pod 때문에
# 바로 재프로비저닝하므로 반드시 FE(컨트롤러가 뜨는 노드)를 0으로 내린 뒤 호출할 것.
terminate_karpenter_nodes() {
  local ids
  ids="$(karpenter_instance_ids)"
  if [[ -z "${ids}" ]]; then
    info "Karpenter 노드(${KARPENTER_NODEPOOL_NAMES[*]}): 없음 — 변경 없음"
    return 0
  fi
  info "Karpenter 노드 종료: $(printf '%s ' ${ids})"
  # shellcheck disable=SC2086
  aws ec2 terminate-instances --instance-ids ${ids} >/dev/null || die "Karpenter 노드 terminate 실패"
  wait_until "Karpenter 노드 전부 종료" _karpenter_all_gone
}
