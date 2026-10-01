# Grafana Alerting / 모니터링 알림 설정 문서

- 작성일: 2026-09-18
- 담당: 부학성 (Observability / Monitoring)
- 관련 브랜치: `V-MoongCheap/MoongCheap-Cloud` `feat/monitoring-alert` (→ `develop` PR 대상)
- 관련 파일:
  - `gitops/platform/monitoring/kube-prometheus-stack/values.yaml`
  - `gitops/platform/observability/alloy-metrics/values.yaml`

> 이 문서는 이번 PR(체크리스트 "Alert" 섹션 + Grafana 대시보드/Ingress 스캐폴드)에 포함된 내용만 다룹니다.
> Grafana Admin Password ExternalSecret / Discord Webhook Secrets Manager 전환은 **다음 PR로 분리**했습니다 (9절 TODO 참고).

---

## 1. 아키텍처 결정 사항

- 알림 경로는 **Grafana Unified Alerting → Discord Webhook**으로 확정 (`docs/cloud_infra_architecture_V2.md` §7.3/§7.5 참조).
- Prometheus 자체 Alertmanager는 사용하지 않음 (`alertmanager.enabled: false` 유지). Grafana Alerting이 평가·라우팅·알림 발송을 전부 담당.
- 알림 규칙(rule), Contact Point, Notification Policy, 커스텀 메시지 템플릿은 전부 **Helm values 기반 provisioning**(`grafana.alerting.*`)으로 관리 — Grafana UI에서 직접 만든 게 아니라 코드로 관리되므로 UI에서는 "Provisioned"로 표시되고 UI 수정이 막혀 있음.
- Discord 웹훅 URL은 git에 올리지 않고, 클러스터에 별도로 생성한 Kubernetes Secret(`grafana-env-secret`)을 통해 환경변수로 주입 → `$__env{DISCORD_WEBHOOK_URL}` 문법으로 참조. **(이번 PR에서는 수동 생성 — 2절 참고. ExternalSecret 전환은 9절 TODO)**
- Grafana 외부 접속 도메인은 `grafana.moongcheap.shop`으로 확정 (Cloudflare Tunnel + Access 뒤). 실제 Ingress 연동은 다른 담당자의 Cloudflare/ingress-nginx 작업 완료 후 진행 — 이번 PR에는 **비활성 스캐폴드만** 포함 (8절 참고).

---

## 2. 사전 준비 (배포 전 반드시 필요 — git에는 없음)

Discord 웹훅 URL을 담은 Secret을 클러스터에 미리 생성해야 합니다. **이 Secret은 git에 커밋하지 않습니다.**

```bash
kubectl create secret generic grafana-env-secret \
  -n monitoring \
  --from-literal=DISCORD_WEBHOOK_URL='https://discord.com/api/webhooks/...'
```

> 이 방식은 임시입니다. 팀 컨벤션(`docs/naming_convention_V2.md` §10, `docs/cloud_infra_architecture_V2.md` §7.1)상 실제로는 AWS Secrets Manager + External Secrets Operator(ESO)로 관리하는 게 맞고, 기존에 Budget Alert에서 쓰던 `moongcheap-develop-infra-discord-secret`을 재사용할 계획입니다. 이번 PR 범위에서는 제외했고 별도 PR로 진행 예정입니다 (9절 TODO).

배포 순서: 위 Secret을 먼저 만든 뒤 → ArgoCD가 `kube-prometheus-stack` Application을 Sync 하도록 합니다. Secret이 없는 상태로 Grafana Pod가 뜨면 `envFromSecret` 참조가 실패합니다.

---

## 3. 알림 규칙 (5종)

모두 `MoongCheap` 폴더 아래 `moongcheap-alerts` 그룹으로 provisioning되며, 평가 주기(`interval`)는 1분입니다.

| UID | 제목 | 데이터소스 | 조건 | Pending 유지시간(`for`) | 심각도 |
|---|---|---|---|---|---|
| `pod-crashloopbackoff` | Pod CrashLoopBackOff | Prometheus | `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1` 이 1개 이상 존재 | 5m | critical |
| `node-not-ready` | Node NotReady | Prometheus | `kube_node_status_condition{condition="Ready", status="true"}` 값이 1 미만 | 5m | critical |
| `host-cpu-high` | CPU 사용률 임계치 초과 | Prometheus (Alloy 수집) | `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` > 80 | 10m | warning |
| `host-mem-high` | 메모리 사용률 임계치 초과 | Prometheus (Alloy 수집) | `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100` > 80 | 10m | warning |
| `pvc-usage-high` | PVC 사용량 임계치 초과 | Prometheus (kubelet 직접 scrape) | `(kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) * 100` > 80 | 10m | warning |

### 3-1. 설계 관련 주의사항

- **CrashLoopBackOff**는 "존재 기반" 메트릭(크래시루프 중인 파드가 있을 때만 시계열 자체가 생김)이라, 정상 상태에서는 쿼리 결과가 원래 없는 게 맞습니다. 이 경우 Grafana가 기본적으로 "데이터 없음"을 이상 상황으로 보고 `DatasourceNoData` 알림을 쏘기 때문에, 이 룰에는 **`noDataState: OK`**를 명시해서 "데이터 없음 = 정상"으로 처리하도록 했습니다.
- **Node NotReady**는 반대로 `kube_node_status_condition{...} == 0`처럼 값 자체를 쿼리에서 필터링하면 안 됩니다(정상일 때 시계열이 아예 사라져서 위와 같은 `DatasourceNoData` 문제 발생). 그래서 쿼리는 필터 없이 원값(0 또는 1)을 그대로 가져오고, **threshold 단계(`evaluator: lt, params: [1]`)에서 "1 미만이면 비정상"으로 판정**하도록 설계했습니다. 이 노드 메트릭은 항상 시계열이 존재하는 타입이라 이 방식이 맞습니다.
- CPU/메모리/PVC 룰은 항상 값이 존재하는 메트릭이라 `noDataState` 기본값 그대로 둬도 됩니다.

---

## 4. Contact Point — Discord

```yaml
name: discord-webhook
type: discord
settings:
  url: $__env{DISCORD_WEBHOOK_URL}
  use_discord_username: true
  title: (커스텀 템플릿 `moongcheap.title` 참조)
  message: (커스텀 템플릿 `moongcheap.message` 참조)
```

---

## 5. Notification Policy

```yaml
receiver: discord-webhook
group_by: ['alertname']
group_wait: 30s        # 같은 그룹의 알림이 처음 발생했을 때 대기 시간
group_interval: 5m     # 같은 그룹에 새 알림이 추가될 때 재전송 주기
repeat_interval: 4h    # 동일 알림이 계속 Firing 상태일 때 반복 알림 주기
```

> 테스트 시 5분 텀이 답답하면 `group_interval`을 일시적으로 30s 정도로 낮춰서 확인하고, 실제 운영에 반영할 때는 반드시 5m으로 되돌려야 합니다. 너무 짧게 두면 반복 알림으로 Discord가 스팸에 가까워집니다.

---

## 6. 커스텀 메시지 템플릿

기본 Grafana 알림 포맷은 라벨을 전부 나열하는 방식이라 가독성이 떨어져서, 운영 채널에서 흔히 쓰는 형태(🔴/✅ 상태 아이콘, 룰 이름, 요약, 발생 시각, 링크)로 커스터마이징했습니다.

```
🔴 [FIRING:N] MoongCheap 알림          ← 제목 (Firing 개수 표시)
🔴 **{alertname}** (심각도: {severity})
{summary}
발생: {StartsAt, KST}
상세보기: {GeneratorURL}
```

Resolved 시:
```
✅ [RESOLVED] MoongCheap 알림
✅ **{alertname}** 복구됨 ({StartsAt} ~ {EndsAt}, KST)
```

`GeneratorURL`은 Grafana `root_url` 설정(`https://grafana.moongcheap.shop/`)을 기준으로 생성됩니다 — 단, 이번 PR에는 Ingress가 아직 비활성이라 실제 배포 후 Ingress가 붙기 전까지는 이 링크가 열리지 않을 수 있습니다 (8절 참고).

### 6-1. 중요한 구현 트러블슈팅 — Helm `tpl` 이스케이프

`grafana.alerting.*` 밑의 값들은 Grafana에 전달되기 전에 **Helm이 `tpl` 함수로 한 번 더 Go 템플릿으로 렌더링**합니다. 그래서 Grafana가 런타임에 해석해야 할 `{{ .Labels.xxx }}`, `{{ define ... }}` 같은 문법을 원본 그대로 쓰면 Helm이 먼저 실행하려다가 에러가 납니다 (`undefined variable`, `template not defined` 등).

**해결책**: `{{`/`}}`를 리터럴로 남기고 싶은 곳은 `{{ \`{{\` }}` / `{{ \`}}\` }}` 처럼 **백틱(raw string)으로 감싸서 한 번 우회**시켜야 합니다. 처음엔 큰따옴표(`"`)로 이스케이프했는데, `grafana.alerting` 값 전체가 한 번 더 `toYaml`로 재직렬화되는 과정에서 큰따옴표가 `\"`로 escape되어 버려서 또 깨졌습니다 — **반드시 백틱을 쓸 것.**

### 6-2. `.Labels.rulename` vs `.Labels.alertname`

`rulename` 라벨은 Grafana가 `DatasourceNoData` 같은 "대체 알림"으로 알림명이 바뀔 때만 원래 룰 제목을 보존하려고 추가하는 특수 라벨입니다. **정상적으로 Firing되는 일반 알림에는 `rulename` 라벨이 없고**, 대신 `alertname` 라벨이 이미 룰 제목을 그대로 담고 있습니다. 템플릿에서는 반드시 **`.Labels.alertname`**을 써야 하며, `.Labels.rulename`을 쓰면 정상 알림에서 이름이 빈 값으로 렌더링됩니다.

### 6-3. 타임존(KST)

Grafana 컨테이너는 기본 UTC로 동작해서 `.StartsAt.Format ...`이 UTC로 찍힙니다. 아래 두 가지를 같이 적용해야 KST로 나옵니다.

- `grafana.env.TZ: "Asia/Seoul"` 추가
- 템플릿에서 `.StartsAt.Format` → **`.StartsAt.Local.Format`** (`.EndsAt`도 동일)

(Grafana 이미지가 distroless라 타임존 데이터베이스가 없으면 `.Local`이 안 먹을 수 있음 — 온프렘 테스트에서는 KST로 정상 표시되는 것까지 확인했고, EKS 배포 후에도 동일하게 확인 필요.)

---

## 7. 테스트 방법

### 7-1. Contact Point 자체 테스트 (웹훅 연결 확인)
Grafana `Alerting > Notification configuration > Contact points`에서 `discord-webhook` 옆 `Test` 버튼 → 실제 룰 발동 없이 즉시 테스트 메시지 발송.

### 7-2. 실제 알림 트리거 (전체 파이프라인 검증)

**Pod CrashLoopBackOff** (가장 안전하고 빠름):
```bash
kubectl run crashloop-test -n monitoring --image=busybox --restart=Always -- sh -c "exit 1"
# 테스트 후
kubectl delete pod crashloop-test -n monitoring
```

**CPU / 메모리** — 실제 스트레스 도구보다 **임계값을 일시적으로 낮춰서 테스트하는 걸 권장**(부하 도구가 코어 수·리소스에 따라 실제로 80%를 못 넘길 수 있음):
```yaml
conditions:
  - evaluator: { type: gt, params: [1] }   # 테스트용, 확인 후 80으로 복원
for: 30s                                    # 테스트용, 확인 후 10m으로 복원
```

**Node NotReady / PVC 사용량 초과**는 실제로 트리거하면 리스크가 있어(노드 다운, 디스크 꽉 채우기), Grafana Explore에서 쿼리 결과값만 확인하는 걸로 충분합니다.

> 위 5개 규칙 전부 온프렘 테스트 클러스터에서 Discord 실제 수신까지 검증 완료. EKS 배포 후 Contact Point Test 버튼으로 최소 1회 재검증 권장 (9절 최종 확인 참고).

---

## 8. Grafana 대시보드 / Ingress 추가 사항 (이번 PR 범위)

### 8-1. Node Exporter Full 대시보드 추가

`grafana.dashboards.moongcheap`에 아래 항목 추가 (기존 3개 대시보드와 동일하게 `MoongCheap` 폴더 아래 provisioning):

```yaml
node-exporter-full:
  gnetId: 1860
  revision: 45
  datasource: Prometheus
```

수동 Import Dashboard ID 1860으로 데이터 정상 수집 확인 완료 → provisioning 방식으로 전환.

### 8-2. Grafana Ingress — 비활성 스캐폴드

```yaml
ingress:
  enabled: false   # TODO: Cloudflare extra_subdomains(grafana) 활성화 + ingress-nginx 배포 확인 후 true
  ingressClassName: nginx   # ingress-nginx 기본 클래스명으로 가정 — 실제 값 다르면 교체
  annotations: {}
  path: /
  hosts:
    - grafana.moongcheap.shop
  tls: []
```

- 호스트명은 팀에서 확정한 `grafana.moongcheap.shop` (Cloudflare Access 뒤)을 반영.
- `enabled: false`라 지금은 아무 영향 없음 — Cloudflare `extra_subdomains`(`terraform/envs/develop/main.tf`, 현재 주석 처리됨)와 ingress-nginx 배포가 끝나면 `enabled: true`로 전환하고 `ingressClassName` 실제 값만 확인하면 바로 연동됨.
- 활성화 전까지 "Grafana 외부 접속 확인" 체크리스트 항목은 보류 상태.

---

## 9. 알려진 이슈 / 트러블슈팅 기록

- **Alloy → Prometheus remote_write 안 되던 문제**: `alloy-metrics`가 `hostNetwork: true`인데 `dnsPolicy`를 `ClusterFirstWithHostNet`으로 명시하지 않아서, 파드가 클러스터 DNS(CoreDNS) 대신 호스트 노드의 DNS(8.8.8.8)를 사용 → `*.svc.cluster.local` 이름 해석 실패 → CPU/메모리 메트릭이 전혀 안 들어오던 문제였음. `controller.dnsPolicy: ClusterFirstWithHostNet` 추가로 해결 (이번 PR 포함).
- **Grafana admin 비밀번호 401 (온프렘 테스트 중 발생, EKS와는 무관)**: Helm이 admin-password Secret을 최초 생성 시점 이후로는 values.yaml이 바뀌어도 덮어쓰지 않는 게 원인이었음. EKS는 신규 배포이므로 최초 부팅 시 `adminPassword: CHANGE_ME`로 정상 적용될 것으로 예상 — 단, 로그인 후 **반드시 실제 운영 비밀번호로 변경**하거나 9절 TODO의 ExternalSecret 전환을 빠르게 진행할 것.

---

## 10. TODO / 후속 작업 (다음 PR)

- [ ] Grafana Admin Password → AWS Secrets Manager + ExternalSecret 전환 (`moongcheap-develop-monitoring-grafana-admin-secret`) — ESO/ClusterSecretStore 배포 확인 후 진행.
- [ ] Discord Webhook(`grafana-env-secret`) → AWS Secrets Manager + ExternalSecret 전환 — 기존 Budget Alert용 `moongcheap-develop-infra-discord-secret` 재사용 여부 팀 확인 필요 (같은 Discord 채널로 갈지, 모니터링 전용 채널을 새로 팔지).
- [ ] Grafana Ingress 활성화 — Cloudflare `extra_subdomains`(grafana) 주석 해제 + ingress-nginx 배포 확인 후 `enabled: true`, `ingressClassName` 실제 값 확정.
- [ ] 위 항목 완료 후 "Grafana 외부 접속 확인", "Admin Password ExternalSecret" 체크리스트 항목 마무리.
- [ ] EKS 배포 후 최종 확인: Prometheus Metric 수집 / Loki Log 수집 / Alloy→Loki 전달 / Grafana Dashboard(4종) 조회 / Discord 알림 재검증.