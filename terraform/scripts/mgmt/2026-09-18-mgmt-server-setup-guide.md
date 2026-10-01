# KT Cloud MGMT 서버 초기 설정 가이드 (Open/Close 자동화)

- **기준**: `MoongCheap-Cloud` 브랜치 `feat/mgmt-open-close`(develop `dcac09e` = PR #27 system-ng 포함 위) — `terraform/scripts/mgmt/` 8개 파일(`reconcile.sh` 포함) + `modules/eks` `fe_min_size`·`system_min_size`=0, 두 Node Group `desired_size` ignore_changes. **이 가이드의 §3 이후는 그 브랜치가 develop에 머지되고 §1의 Terraform apply가 끝난 뒤에 실행한다.**
- **목적**: KT Cloud VM은 IaC로 만들 수 없으므로, MGMT 서버에 **터미널로 직접 접속해서 한 번 해줘야 하는 것**을 순서대로 적었다. 이후 운영(스케줄 변경·스크립트 수정)은 전부 Git PR로만 하고 서버에는 손대지 않는다.
- **범위 밖**: KT Cloud VM 생성·네트워크·OS 설치 자체(콘솔 작업). Backup Storage(설계서 3.6, 별도 [확정 필요]).
- 관련 문서: `docs/cost-management-runbook_V2.md` 7.1(Open/Close 절차·순서), `docs/cloud_infra_architecture_V2.md` 3.5·8.3·8.5(MGMT 역할·인증·보호 정책), `2026-09-18-feature-status-and-review.md` C-7

---

## 0. 전제 — 이 순서를 지킬 것

| 순서 | 어디서 | 무엇 | 안 하면 |
|---|---|---|---|
| 1 | 인프라 담당자 로컬 | `feat/mgmt-open-close` → develop 머지 → `terraform apply` (§1) | `close-infra.sh`가 "desired=0이 min=1 범위 밖" 에러로 종료 |
| 2 | AWS 콘솔 (계정 소유자) | MGMT 전용 IAM User + Access Key 발급 (§2) | 스크립트가 AWS 인증 실패로 종료 |
| 3 | MGMT 서버 터미널 | 패키지·타임존·디렉토리·로그 파일·리포 클론·자격증명 (§3~§6) | — |
| 4 | MGMT 서버 터미널 | 수동 테스트 → crontab 등록 (§7~§8) | — |

---

## 1. [로컬] Terraform 선행 apply

`feat/mgmt-open-close`가 develop에 머지된 뒤, 인프라 담당자가 로컬에서:

```bash
cd MoongCheap-Cloud/terraform/envs/develop
terraform plan    # 기대: aws_eks_node_group.fe ~ min_size 1 -> 0, aws_eks_node_group.system ~ min_size 2 -> 0 (in-place 2건)
terraform apply
```

이 apply가 하는 일은 FE·System Node Group `min_size`를 0으로 내리는 것뿐이다(노드 수 변화 없음). 동시에 `desired_size`가 `ignore_changes`로 들어가 이후 스크립트가 desired를 0↔2로 바꿔도 `terraform plan`에 diff가 안 뜬다.

---

## 2. [AWS 콘솔] MGMT 전용 IAM User

계정 소유자(상우님)가 콘솔에서 만든다. **팀원 개인 IAM User(`v-infra-*`)의 Key를 MGMT 서버에 두지 않는다** — 개인 Key는 cluster-admin 권한이라 서버가 털리면 클러스터 전체가 노출된다.

1. IAM → Users → Create user. 이름은 `[확정 필요]`(제안: `moongcheap-mgmt`). 콘솔 접근 없음.
2. Permissions → **Create policy → JSON**에 리포의 `terraform/scripts/mgmt/mgmt-iam-policy.json` 내용을 그대로 붙임. 정책 이름 제안: `moongcheap-develop-mgmt-openclose-policy`(네이밍 3.4 패턴).
3. 그 정책만 attach. `AdministratorAccess` 등 관리형 정책 금지.
4. Security credentials → **Create access key** → Use case "Application running outside AWS" → Key ID·Secret을 **한 번만** 안전한 경로로 전달(Discord 공개 채널 금지). 이 Key는 §6에서 MGMT 서버에만 입력하고 어디에도 저장하지 않는다.

정책이 허용하는 것(최소 권한):

| 동작 | 범위 |
|---|---|
| `sts:GetCallerIdentity`, `ec2:DescribeInstances/InstanceStatus`, `eks:DescribeCluster/Nodegroup`, `eks:ListNodegroups` | 전체(읽기) |
| `eks:UpdateNodegroupConfig` | `moongcheap-develop-eks`의 Node Group만 |
| `ec2:StartInstances`, `ec2:StopInstances` | `Name=moongcheap-develop-nat` 태그 인스턴스만 |
| `ec2:TerminateInstances` | `kubernetes.io/cluster/moongcheap-develop-eks=owned` **그리고** `karpenter.sh/nodepool` 태그가 있는 인스턴스만 |

이 정책으로는 RDS·S3·Secrets Manager·IAM·Terraform State에 아예 접근할 수 없다.

> 후속 결정: 이 IAM User를 Terraform `modules/iam`으로 옮길지(권장 — 정책 JSON을 코드로 관리). Access Key 자체는 어차피 콘솔/CLI 수동 발급이라 Terraform State에 안 들어간다.

---

## 3. [MGMT 서버] OS 준비

Ubuntu 22.04 기준(다른 배포판은 패키지 명령만 치환). 여기부터는 MGMT 서버에 SSH 접속해서 실행.

### 3.1 타임존 — 반드시 Asia/Seoul

cron은 서버 시각을 그대로 쓴다. `schedule.csv`의 `open,09:00,mon-fri`가 한국 09:00이 되려면:

```bash
sudo timedatectl set-timezone Asia/Seoul
timedatectl | grep "Time zone"     # Asia/Seoul (KST, +0900)
date                               # 현재 한국 시각인지 눈으로 확인
```

### 3.2 패키지

```bash
sudo apt-get update
sudo apt-get install -y git cron unzip curl util-linux   # util-linux: flock (보통 이미 있음)
sudo systemctl enable --now cron

# AWS CLI v2 (apt의 awscli v1은 쓰지 않음)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install
aws --version        # aws-cli/2.x
which aws            # /usr/local/bin/aws  ← common.sh가 PATH에 이 경로를 넣어둠
git --version
```

### 3.3 실행 사용자

스크립트는 **일반 사용자**로 돈다(root cron 아님). 기존 로그인 사용자(예: `ubuntu`)를 그대로 쓰거나 전용 사용자를 만든다. 아래는 `ubuntu` 기준. 전용 사용자를 만들면 이후 명령의 `ubuntu`를 치환.

```bash
whoami    # ubuntu
```

---

## 4. [MGMT 서버] 디렉토리·로그 파일 (sudo 필요한 유일한 구간)

```bash
# 리포가 들어갈 디렉토리 — 실행 사용자 소유
sudo mkdir -p /opt/moongcheap
sudo chown ubuntu:ubuntu /opt/moongcheap

# 로그 파일 — /var/log는 root 소유라 파일을 먼저 만들어 소유권을 넘겨야 한다
sudo touch /var/log/moongcheap-infra.log
sudo chown ubuntu:ubuntu /var/log/moongcheap-infra.log
sudo chmod 640 /var/log/moongcheap-infra.log

# logrotate (선택 — 하루 몇 줄 수준이라 없어도 됨)
sudo tee /etc/logrotate.d/moongcheap-infra >/dev/null <<'EOF'
/var/log/moongcheap-infra.log {
    monthly
    rotate 6
    compress
    missingok
    notifempty
    create 640 ubuntu ubuntu
}
EOF
```

로그 파일 권한을 안 넘기면 스크립트가 죽지는 않고 `LOG_FILE에 쓸 수 없어 stderr로만 기록함` 경고를 내며 stderr로만 남긴다(cron이면 메일/journal로 감).

---

## 5. [MGMT 서버] 리포 클론 — develop 브랜치

```bash
cd /opt/moongcheap
git clone -b develop https://github.com/V-MoongCheap/MoongCheap-Cloud.git
cd MoongCheap-Cloud
git branch --show-current      # develop  ← sync-repo.sh가 이 브랜치가 아니면 종료함
ls -l terraform/scripts/mgmt/  # *.sh에 x 권한이 있어야 함(git이 유지). 없으면 아래
chmod +x terraform/scripts/mgmt/*.sh
```

- public 리포라 인증 없이 clone/pull 된다. private으로 바뀌면 read-only Deploy Key를 이 서버에 등록해야 한다(`GIT_TERMINAL_PROMPT=0`이라 자격증명 프롬프트에서 멈추지 않고 실패로 기록됨).
- **이 서버에서 리포 파일을 직접 고치지 않는다.** 고치면 `sync-repo.sh`가 "로컬 변경사항 있음"으로 pull을 멈추고, 이후 스케줄 변경이 반영되지 않는다. 실수로 고쳤으면 `git -C /opt/moongcheap/MoongCheap-Cloud checkout -- .`로 되돌린다.

---

## 6. [MGMT 서버] AWS 자격증명 — §2에서 받은 Key

```bash
aws configure               # profile: default
#   AWS Access Key ID     : <§2에서 받은 값>
#   AWS Secret Access Key : <§2에서 받은 값>
#   Default region name   : ap-northeast-2
#   Default output format : json

chmod 700 ~/.aws && chmod 600 ~/.aws/credentials
aws sts get-caller-identity     # Arn이 arn:aws:iam::...:user/<MGMT IAM User>인지 확인
```

- 다른 profile 이름을 쓰려면 crontab 줄 앞에 `AWS_PROFILE=<이름>`을 주거나 `common.sh`의 기본값을 바꾸는 PR을 낸다. 기본은 `default`.
- Key를 `.bashrc`, 스크립트, 리포 어디에도 적지 않는다. 이 파일 하나에만 있다.

권한이 딱 맞는지 바로 확인(읽기만 하므로 안전):

```bash
cd /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt
bash -c 'source ./common.sh; check_aws_auth; nat_instance; for e in "${MANAGED_NODEGROUPS[@]}"; do nodegroup_summary "${e%%=*}"; done; karpenter_instance_ids | wc -l'
# 기대 출력 예:
#   ... [INFO] AWS 인증 OK: arn:aws:iam::...:user/moongcheap-mgmt
#   i-0xxxxxxxx	running
#   moongcheap-develop-system-ng: ACTIVE desired=2 (min=0, max=2) running=2   ← S-1 전이면 "(없음)" — 스크립트는 WARN 후 건너뜀
#   moongcheap-develop-fe-ng: ACTIVE desired=2 (min=0, max=2) running=2       ← min이 0이어야 함(§1 apply 완료 확인). 1이면 §1 미완
#   0
```

`AccessDenied`가 나오면 §2 정책의 Resource ARN·태그 조건이 실제 리소스와 맞는지 확인(계정 ID `840851421204`, 리전 `ap-northeast-2`).

---

## 7. [MGMT 서버] 수동 테스트 — 순서대로, 결과 확인하며

### 7.1 crontab 갱신 (AWS 안 건드림)

```bash
cd /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt
./update-cron.sh
crontab -l
```

기대: `# BEGIN MOONGCHEAP MANAGED CRON` ~ `# END ...` 사이에 `schedule.csv`의 `enabled=true` 행 2개(평일 09:00 open / 22:00 close)가 **메모 주석 + cron 줄** 쌍으로 절대경로로 들어감(§8 예시). 기존 crontab에 있던 다른 항목은 그대로. 백업은 `~/.moongcheap/crontab-backup/`.

### 7.2 리포 동기화 (AWS 안 건드림)

```bash
./sync-repo.sh
```

기대: `이미 최신 (xxxxxxx)` 또는 `pull --ff-only: ... → ...`. 로컬 변경·브랜치 불일치면 ERROR로 종료하며 pull 안 함.

### 7.3 Close → Open 실제 1회 (팀에 공지 후, 작업 시간 밖에서)

**노드가 실제로 내려간다.** 실행 중인 Pod는 drain 없이 죽으므로 Jenkins 빌드가 없는 시간에, 팀 채널에 알린 뒤 실행.

```bash
./close-infra.sh
# 기대 로그 순서: AWS 인증 OK → system-ng·fe-ng desired 2 → 0 (요청 먼저 둘 다, 대기는 순서대로) → 인스턴스 0대 확인
#              → Karpenter 노드 없음(또는 종료) → NAT stop → stopped
# system-ng가 아직 없으면 "[WARN] ... Node Group 없음 — 건너뜀" 후 계속 진행(정상)
# 소요: 3~6분

aws ec2 describe-instances --filters Name=tag:Name,Values=moongcheap-develop-nat --query 'Reservations[].Instances[].State.Name' --output text   # stopped
aws eks describe-nodegroup --cluster-name moongcheap-develop-eks --nodegroup-name moongcheap-develop-fe-ng --query 'nodegroup.scalingConfig' # desiredSize 0

./open-infra.sh
# 기대: NAT start → running → system-ng·fe-ng desired 0 → 2 → 각 인스턴스 2대 → ACTIVE
# 소요: 4~7분 (노드 join 포함)

kubectl get nodes   # (로컬에서, kubectl 접근 가능한 사람이) system 2대 + FE 2대 Ready 확인
```

두 번 연속 실행해도 `이미 running — 변경 없음` / `desired 이미 2 — 변경 없음`으로 통과해야 한다(idempotent 확인).

### 7.4 Terraform drift 확인 (로컬, 인프라 담당자)

Close 상태에서 `terraform plan`을 돌려 **diff가 없는지** 확인한다. `desired_size` 변경이 뜨면 `ignore_changes`가 적용되지 않은 것(§1 미완).

---

## 8. [MGMT 서버] cron 등록 — sync-repo만 사람이 등록

Open/Close 줄은 `update-cron.sh`가 관리하므로 **직접 쓰지 않는다**. 사람이 등록하는 건 `sync-repo.sh` 한 줄:

```bash
crontab -e
```

Marker 구간 **밖**(위쪽)에 추가:

```cron
*/5 * * * * /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/sync-repo.sh
```

저장 후 최종 모습:

```cron
*/5 * * * * /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/sync-repo.sh

# BEGIN MOONGCHEAP MANAGED CRON
# generated by update-cron.sh from terraform/scripts/mgmt/schedule.csv (...)
# 직접 수정 금지 — schedule.csv를 고쳐 develop에 머지하면 sync-repo.sh가 반영한다
# 시각은 서버 timezone 기준(Asia/Seoul로 설정돼 있어야 함 — setup guide 참고)
# open 09:00 mon-fri — 평일 기본 운영 시작
0 9 * * 1,2,3,4,5 /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/open-infra.sh
# close 22:00 mon-fri — 평일 기본 운영 종료
0 22 * * 1,2,3,4,5 /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/close-infra.sh
# END MOONGCHEAP MANAGED CRON
```

5분 뒤 `tail -5 /var/log/moongcheap-infra.log`에 `[sync-repo.sh] ... 이미 최신` 이 찍히면 cron 동작 확인 끝.

---

## 9. 운영 중 확인 방법

### 9.1 지금 스케줄이 뭔지

```bash
crontab -l                                      # 실제 등록된 것
cat /opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/schedule.csv   # Git 기준
```

둘이 다르면 아직 sync 전(최대 5분) 또는 sync가 막힌 것 → 9.3.

### 9.2 Open/Close가 돌았는지

```bash
tail -50 /var/log/moongcheap-infra.log
grep -E '\[(open|close)-infra.sh\].*(시작|종료)' /var/log/moongcheap-infra.log | tail -10
```

한 회차의 정상 로그는 `시작: Close ...` → 단계별 INFO → `종료: 성공 (소요 NNNs)`. 실패는 `[ERROR] 실패 (exit=N) at <파일>:<줄>: <명령>` 한 줄이 **어느 단계에서 죽었는지** 알려주고, 이어서 `종료: 실패`.

### 9.3 실패 유형별 확인

| 로그에 보이는 것 | 원인 | 조치 |
|---|---|---|
| `AWS 인증 실패 (profile=default ...)` | Key 만료·삭제, `~/.aws/credentials` 손상 | §6 다시. 콘솔에서 Key 상태 확인 |
| `AccessDenied` / `UnauthorizedOperation` | 정책 부족 또는 리소스 이름·태그 변경 | §2 정책과 실제 태그(`Name=moongcheap-develop-nat`, nodepool 태그) 대조 |
| `목표 desired=0가 min=1~max=2 범위 밖` | §1 Terraform apply 안 됨 | 인프라 담당자에게 apply 요청 |
| `NAT Instance(...) 조회 결과 0건` | NAT가 terminated(재생성 중) 또는 Name 태그 변경 | Terraform 쪽 확인. 재생성 후엔 새 인스턴스를 태그로 자동 인식하므로 스크립트 수정 불필요 |
| `타임아웃(900s): ...` | 노드 join/종료가 15분 넘게 걸림 | AWS 콘솔에서 Node Group Health issues, NAT 상태 확인. 재실행은 안전(idempotent) |
| `이미 실행 중 (...lock)` | 이전 회차가 아직 안 끝남(보통 타임아웃 대기 중) | 이전 회차 로그 확인 후 기다림 |
| `[sync-repo.sh] 로컬 변경사항 있음` | 서버에서 파일을 직접 고침 | `git -C /opt/moongcheap/MoongCheap-Cloud checkout -- .` |
| `[sync-repo.sh] fast-forward 불가` | develop 이력 재작성(force-push) 또는 서버에서 커밋 | 팀 확인 후 인프라 담당자가 서버에서 수동 정리(`git fetch && git reset --hard origin/develop` — 이 경우만) |
| `[sync-repo.sh] git fetch 실패` | GitHub 접속 불가, 리포 private 전환 | 네트워크·Deploy Key 확인 |
| `[update-cron.sh] line N: 헤더 불일치 / time은 HH:MM / 요일 이름 잘못됨 / 필드가 5개를 넘음` | `schedule.csv` 오타(memo에 콤마 포함) | crontab은 이전 값 유지됨. CSV 고쳐 PR |
| `[open/close-infra.sh] [WARN] ...system-ng: Node Group 없음 — 건너뜀` | Node Group 이름 불일치(system-ng는 PR #27로 이미 존재) | `common.sh MANAGED_NODEGROUPS`와 `aws eks list-nodegroups` 대조 |
| `[sync-repo.sh] [WARN] 스케줄 변경으로 지금 기대 상태가 open → close로 바뀜 — reconcile 실행` | 정상 — `schedule.csv` 변경이 "지금 있어야 할 상태"를 바꿈 | 의도한 변경인지 PR 확인. 의도가 아니면 CSV 되돌리는 PR(되돌리면 다시 open됨) |
| `Marker가 손상됨(BEGIN=1, END=0)` | 누가 `crontab -e`로 관리 구간을 건드림 | `crontab -e`로 BEGIN/END 쌍 복구 또는 구간 통째로 삭제 후 `./update-cron.sh` |

cron 자체가 안 도는 것 같으면: `systemctl status cron`, `grep CRON /var/log/syslog | tail` (또는 `journalctl -u cron -n 30`).

### 9.4 임시 연장·긴급 Open/Close

Runbook 7.1의 "익일 01:00 연장", "주말 요청 운영"은 스케줄을 바꾸지 않고 **서버에서 수동 실행**한다:

```bash
/opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/open-infra.sh    # 지금 열기
/opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/close-infra.sh   # 지금 닫기
/opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/reconcile.sh --dry-run   # 스케줄상 지금 있어야 할 상태만 출력
/opt/moongcheap/MoongCheap-Cloud/terraform/scripts/mgmt/reconcile.sh             # 그 상태로 맞춤 (서버 다운으로 cron 놓쳤을 때)
```

수동으로 연 상태는 스케줄의 다음 close 시각에 자동으로 닫힌다. 수동 연장 중에는 `reconcile.sh`를 돌리지 말 것(스케줄 기준으로 되돌림). `schedule.csv` PR로도 당일 변경이 가능하다 — 머지 후 5분 안에 "지금 기대 상태"가 바뀌면 자동으로 open/close된다(Runbook 7.1).

정기 스케줄 자체를 바꾸려면 `schedule.csv` PR. 형식은 `action,time,days,enabled,memo`(파일 상단 주석에 설명). 예: 주말 토요일 12:00 Open + 일요일 01:00 Close 추가 → `open,12:00,sat,true,토요일 운영` / `close,01:00,sun,true,토요일 운영 종료`. 이미 들어 있는 `enabled=false` 주말 예시 행을 `true`로 바꿔도 된다.

---

## 10. 이 가이드 이후에 남는 결정·작업

- [ ] MGMT IAM User 이름·생성 위치(콘솔 vs Terraform `modules/iam`) — 설계서 3.5 [확정 필요]
- [x] ~~S-1 system-ng Terraform~~ PR #27로 생성됨(`a951ce9`). `min_size=0` + `desired_size` ignore_changes는 `feat/mgmt-open-close`에서 추가 → §1 apply에 포함. Label `workload=system`·taint 여부는 설계서 4.2 개정(J-6)에서 확정
- [ ] BE·AI AZ 정책(D-4) — Open 후 PVC AZ 불일치로 Jenkins/Prometheus Pod Pending 가능성
- [ ] Close 전 알림(Discord) — 현재 없음. 필요하면 `close-infra.sh` 앞단에 Webhook 호출 추가(Webhook은 Secrets Manager에서 읽어야 하므로 IAM 정책 추가 필요)
- [ ] MGMT 서버 Spec·Backup Storage(설계서 3.6) — 별건
