# Monitoring & Logging (kube-prometheus-stack / Loki / Grafana Alloy)

MoongCheap EKS 클러스터의 메트릭·로그 수집 스택 구현 문서. `gitops/platform/`
아래의 Platform 컴포넌트 중 모니터링/로깅 파이프라인에 해당하는 부분을 설명한다.

Repository: `https://github.com/V-MoongCheap/MoongCheap-Cloud.git`

---

## 1. 구성 개요

메트릭은 `kube-prometheus-stack`(Prometheus + Grafana)이, 로그는 `Loki`가 저장·조회를
담당한다. 두 백엔드로 실제 데이터를 모아서 보내는 수집 에이전트로는 `Grafana Alloy`를
사용했으며, 호스트 메트릭 수집과 컨테이너 로그 수집을 Alloy 하나로 통합해서 처리한다.

- `kube-state-metrics`, `kubelet`/`cAdvisor`, `kube-apiserver` 등은 `kube-prometheus-stack`
  차트가 기본 제공하는 ServiceMonitor를 통해 Prometheus가 **직접 scrape** 한다.
- Alloy는 **호스트 OS 레벨 메트릭**과 **컨테이너 로그 수집**을 담당하며, 수집한 데이터는
  Alloy가 각각 Prometheus로 `remote_write`, Loki로 `loki.write`를 통해 push하는 구조다.

---

## 2. 디렉터리 구조

```text
gitops/platform/
├── monitoring/
│   ├── kube-prometheus-stack/
│   │   ├── config.yaml
│   │   └── values.yaml
│   └── loki/
│       ├── config.yaml
│       └── values.yaml
└── observability/
    ├── alloy-metrics/
    │   ├── config.yaml
    │   └── values.yaml
    └── alloy-logs/
        ├── config.yaml
        └── values.yaml
```

Prometheus/Grafana/Loki처럼 데이터를 저장·조회하는 백엔드는 `monitoring/`에, Alloy처럼
데이터를 수집해서 보내는 에이전트는 `observability/`에 분류했다.

---

## 3. 컴포넌트별 상세

### kube-prometheus-stack

- Chart: `prometheus-community/kube-prometheus-stack`
- Namespace: `monitoring`
- `nodeExporter.enabled: false` — 호스트 메트릭은 Alloy가 수집하므로 차트 내장 옵션은 끔
- `prometheus.prometheusSpec.enableRemoteWriteReceiver: true` — Alloy의 remote_write를
  받으려면 반드시 켜야 함 (기본값 꺼져있음)
- Grafana가 함께 설치됨. `additionalDataSources`로 Loki 데이터소스를 자동 등록

### Loki

- Chart: `grafana/loki`
- `deploymentMode: SingleBinary` + 로컬 파일시스템 스토리지로 최소 구성
- `chunksCache.enabled: false`, `resultsCache.enabled: false` — 기본 내장 memcached
  캐시가 리소스를 많이 잡아먹어서 비활성화 (필요시 나중에 다시 켤 수 있음)
- 접점은 `gateway`(nginx) 서비스 하나 (`<release-name>-gateway`)

### Alloy - metrics (`alloy-metrics`)

- Chart: `grafana/alloy`, DaemonSet으로 배포 (노드마다 1개)
- `prometheus.exporter.unix` 컴포넌트로 호스트 CPU/메모리/디스크 등 수집
- 수집한 메트릭은 `prometheus.remote_write`로 kube-prometheus-stack의 Prometheus에 push
- 자기 자신의 호스트만 보는 구조라 클러스터 전체를 뒤지는 discovery가 없고, 따라서
  다중 인스턴스 간 중복 수집 문제(clustering)가 발생하지 않음

### Alloy - logs (`alloy-logs`)

- Chart: `grafana/alloy`, DaemonSet으로 배포 (노드마다 1개)
- `loki.source.kubernetes` 컴포넌트로 Kubernetes API를 통해 파드 로그를 tail
  (호스트 로그 경로를 마운트할 필요가 없는 방식)
- `discovery.kubernetes`의 `spec.nodeName` 셀렉터로 자기 노드의 파드만 대상으로 삼음
- 수집한 로그는 `loki.write`로 Loki gateway에 push

---

## 4. ArgoCD 배포 방식 (ApplicationSet 자동 탐색)

Platform 컴포넌트는 개별 Application을 손으로 만들지 않고, **Git File Generator 기반
ApplicationSet 하나**가 `gitops/platform/**/config.yaml`을 자동으로 찾아서 Application을
생성한다.

```text
gitops/argocd/
├── projects/
│   └── platform-project.yaml     # AppProject: moongcheap-platform
└── applicationset-platform.yaml  # 자동 탐색 ApplicationSet
```

`config.yaml`은 차트 정보만 담는다.

```yaml
name: kube-prometheus-stack
namespace: monitoring

helm:
  repoURL: https://prometheus-community.github.io/helm-charts
  chart: kube-prometheus-stack
  version: "90.0.0"
```

같은 디렉터리의 `values.yaml`이 해당 Helm 릴리스의 values로 자동 사용된다. `applicationset-platform.yaml`은
멀티소스 Application 템플릿을 생성한다 — 1번 source는 공식 Helm 저장소의 차트, 2번 source는
이 저장소(`ref: values`) 자체이며, 1번 source가 `$values/{{ .path.path }}/values.yaml`로
2번 source의 values 파일을 참조한다.

```yaml
generators:
  - git:
      repoURL: https://github.com/V-MoongCheap/MoongCheap-Cloud.git
      revision: main
      files:
        - path: gitops/platform/**/config.yaml

template:
  spec:
    project: moongcheap-platform
    sources:
      - repoURL: "{{ .helm.repoURL }}"
        chart: "{{ .helm.chart }}"
        targetRevision: "{{ .helm.version }}"
        helm:
          releaseName: "{{ .name }}"
          valueFiles:
            - $values/{{ .path.path }}/values.yaml
      - repoURL: https://github.com/V-MoongCheap/MoongCheap-Cloud.git
        targetRevision: main
        ref: values
    syncPolicy:
      automated:
        prune: true
        self_heal: true
      syncOptions:
        - CreateNamespace=true
        - ServerSideApply=true   # Prometheus Operator CRD가 커서 client-side apply 시
                                  # annotation 크기 제한(262144 bytes) 초과 에러가 남
```

새로운 Platform 컴포넌트를 추가할 때 이 ApplicationSet 파일을 수정할 필요가 없다 —
`gitops/platform/<카테고리>/<이름>/`에 `config.yaml` + `values.yaml`만 추가하면 자동으로
탐색되어 Application이 생긴다.

### AppProject (`moongcheap-platform`)

Platform 컴포넌트가 쓰는 소스/목적지를 제한한다.

```yaml
sourceRepos:
  - https://github.com/V-MoongCheap/MoongCheap-Cloud.git
  - https://prometheus-community.github.io/helm-charts
  - https://grafana.github.io/helm-charts

destinations:
  - server: https://kubernetes.default.svc
    namespace: monitoring
  - server: https://kubernetes.default.svc
    namespace: kube-system   # kube-prometheus-stack이 CoreDNS 메트릭 수집용 Service를
                              # kube-system에 만들기 때문에 필요
```

Helm 차트를 새로 추가할 때 그 차트의 저장소 URL이 `sourceRepos`에 없으면 ArgoCD가
"source is not permitted in project" 에러를 내며 거부하니, 새 컴포넌트 추가 시 이 목록도
같이 업데이트해야 한다.

---

## 5. 배포 흐름 요약

```text
gitops/platform/**/config.yaml 추가/수정
        ↓ git push
ApplicationSet (Git File Generator)이 감지
        ↓
Application 자동 생성/갱신 (project: moongcheap-platform)
        ↓
ArgoCD가 Helm 차트 + values.yaml을 렌더링해서 동기화 (automated sync)
        ↓
monitoring 네임스페이스에 리소스 배포
```

---

## 6. 동작 확인 방법

1. `kubectl get applicationset,application -n argocd` — `kube-prometheus-stack`,
   `loki`, `alloy-metrics`, `alloy-logs` 4개 Application이 Synced/Healthy인지 확인
2. `kubectl get pods -n monitoring` — `alloy-metrics-*`/`alloy-logs-*`가 노드 수만큼
   떠 있는지 확인
3. Grafana **Explore** → Prometheus 데이터소스 → `node_cpu_seconds_total` 쿼리로
   Alloy → remote_write → Prometheus 경로 확인
4. Grafana **Explore** → Loki 데이터소스 → `{namespace="kube-system"}` 쿼리로
   Alloy → loki.write → Loki 경로 확인
5. (디버깅용) Alloy 파드의 12345 포트로 접속하면 컴포넌트별 파이프라인 상태와
   Live Debugging을 UI로 확인 가능

로컬 검증은 자체 VMware on-prem k9s 클러스터 + 자체 Gitea 인스턴스로 진행했고, 실제 EKS
환경에서는 위 저장소 주소(GitHub)와 `revision: main` 확인 후 테스트한다.

---

## 7. 도메인 연결 후 계획: Ingress 전환

지금은 Grafana / Prometheus / Alloy가 각각 별도 `LoadBalancer` 서비스로 노출되어 있다
(사설 IP로만 접근 가능한 임시 상태). 도메인이 연결되면 `01_cloudflared_ingress`에서
쓰는 것과 동일한 방식으로 서브도메인별 Ingress를 추가하고, 각 서비스는 `ClusterIP`로
바꿀 예정이다.

**서브도메인 매핑 (예시)**

| 서브도메인 | 대상 |
| --- | --- |
| `grafana.cloud-learning.site` | Grafana |
| `prometheus.cloud-learning.site` | Prometheus |
| `alloy.cloud-learning.site` | Alloy UI (디버깅용, 필요할 때만 노출) |

**kube-prometheus-stack-values.yaml 변경**

Grafana/Prometheus는 차트 자체에 `ingress` 옵션이 내장되어 있어서 values만 바꾸면 된다.

```yaml
grafana:
  service:
    type: ClusterIP        # LoadBalancer -> ClusterIP
  ingress:
    enabled: true
    ingressClassName: <01_cloudflared_ingress에서 쓰는 ingressClassName>
    hosts:
      - grafana.cloud-learning.site
    path: /

prometheus:
  service:
    type: ClusterIP        # LoadBalancer -> ClusterIP
  ingress:
    enabled: true
    ingressClassName: <01_cloudflared_ingress에서 쓰는 ingressClassName>
    hosts:
      - prometheus.cloud-learning.site
    paths:
      - /
```

**alloy-metrics-values.yaml / alloy-logs-values.yaml 변경**

```yaml
service:
  type: ClusterIP          # LoadBalancer -> ClusterIP
```

Alloy 차트에는 kube-prometheus-stack처럼 내장된 `ingress` 옵션이 없으므로, 필요하면
별도 `Ingress` 매니페스트를 추가해서 처리한다 (UI는 디버깅용이라 굳이 도메인을 안
붙이고 `kubectl port-forward`로만 써도 무방하다).

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: alloy-metrics-ui
  namespace: monitoring
spec:
  ingressClassName: <01_cloudflared_ingress에서 쓰는 ingressClassName>
  rules:
    - host: alloy.cloud-learning.site
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: alloy-metrics
                port:
                  number: 12345
```

`ingressClassName`과 실제 서브도메인/도메인은 `01_cloudflared_ingress`에서 이미 쓰고
있는 값에 맞춰서 결정한다 (ArgoCD가 `cloud-learning.site` 도메인을 쓰고 있던 것과 동일한
패턴).

---

## 8. Grafana 대시보드 프로비저닝 + 플러그인 버그 수정 (작업 기록)

### 8.1 Grafana 13.x 플러그인 자동 업데이트 버그 수정

**증상**: `kube-prometheus-stack-values.yaml`의 `grafana:` 블록에 대시보드 프로비저닝
설정(8.2절)을 추가하고 배포했더니, 새로 추가한 대시보드뿐 아니라 차트가 기본 제공하던
기존 대시보드까지 포함해 Grafana 전체에서 패널이 전부 "No data"로 뜨고, Data Sources
페이지에서 Prometheus/Loki가 "Data source not found"로 표시됨.

**원인**: 대시보드 설정 변경으로 Grafana Pod가 재시작되면서, 평소엔 드러나지 않던 별개의
버그가 함께 트리거됨. Grafana 13.x는 파드가 뜰 때마다 `plugin.backgroundinstaller`라는
백그라운드 프로세스가 Prometheus/Loki를 포함한 내장(bundled) 플러그인들을 grafana.com
카탈로그에서 최신 버전으로 자동 업데이트하려고 시도하는데, 우리가 쓰는
`grafana/grafana:13.2.1-distroless` 이미지는 플러그인 디렉터리
(`/usr/share/grafana/data/plugins-bundled/`)가 read-only라서 이 시도가 매번
`unlinkat ...: read-only file system` 에러로 실패한다. 이 실패 과정에서 플러그인
등록 자체가 깨지면서 `Could not find plugin definition for data source`
(datasource_type=loki, datasource_type=prometheus) 에러가 발생하고, 그 결과 이미
정상적으로 프로비저닝되어 있던 데이터소스 설정까지 무효화되어 전체 대시보드가
연쇄적으로 망가진 것으로 확인됨. 즉 대시보드 프로비저닝 자체의 문제가 아니라, 그로 인한
재시작이 우연히 이 잠재 버그를 표면화시킨 것.

**조치**: 이 자동 업데이트 시도 자체를 비활성화.

```yaml
grafana:
  env:
    GF_PLUGINS_PREINSTALL_DISABLED: "true"
```

적용 후 Data Sources 페이지 및 기존/신규 대시보드 모두 정상화됨을 확인.

### 8.2 MoongCheap 대시보드 3종 프로비저닝 추가

`kube-prometheus-stack-values.yaml`의 `grafana:` 블록에 아래 설정을 추가해서, 전용
`MoongCheap` 폴더에 대시보드 3종을 자동 프로비저닝하도록 구성.

```yaml
grafana:
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'moongcheap'
          orgId: 1
          folder: 'MoongCheap'
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/moongcheap
  dashboards:
    moongcheap:
      k8s-pods-view:
        gnetId: 15760
        revision: 39
        datasource: Prometheus
      springboot-pods:
        gnetId: 24605
        revision: 1
        datasource: Prometheus
      loki-logs:
        gnetId: 24574
        revision: 2
        datasource: Loki
```

각 대시보드는 grafana.com의 커뮤니티 대시보드를 `gnetId`로 참조하며, Grafana Pod의
`download-dashboards` initContainer가 시작 시점에 해당 JSON을 내려받아 프로비저닝한다.

| 대시보드 | gnetId | 용도 |
| --- | --- | --- |
| `k8s-pods-view` | 15760 (rev 39) | Kubernetes / Views / Pods — Pod 단위 리소스/상태 대시보드 |
| `springboot-pods` | 24605 (rev 1) | Kubernetes Deployment Pods & Springboot — BE 팀이 `/actuator/prometheus`로 메트릭을 노출하기 전까지는 No data가 정상 |
| `loki-logs` | 24574 (rev 2) | Logging Dashboard via Loki v3 — Alloy → Loki 로그 확인용 |

**주의 (label 레이아웃)**: `k8s-pods-view` 대시보드의 상단 필터 변수 중 `job`은
`kube_pod_info` 기준으로 정의되어 있어 항상 `kube-state-metrics`만 선택 가능하며,
이는 정상 동작이다(변수를 잘못 만든 게 아님). 반면 `cluster` 변수는
`label_values(..., cluster)` 쿼리로 정의되어 있는데, 지금 클러스터의 Prometheus에는
`cluster` 레이블이 붙는 시계열이 전혀 없어 옵션이 비어 있다. `prometheus.prometheusSpec.externalLabels`에
`cluster` 값을 추가해도 Prometheus의 `external_labels`는 federation/remote_write/Alertmanager
등 **외부 통신에만** 붙는 레이블이라 로컬 쿼리(Grafana가 보는 값 포함)에는 반영되지
않으므로 이 방법으로는 해결되지 않는다. 이 값은 현재 온프레미스 단일 클러스터에서는
당장 막힌 문제가 아니라고 판단해 손대지 않고 그대로 둔 상태이며, AWS EKS로 옮길 때
다시 검토한다.

### 8.3 알림(Alertmanager / Grafana Alerting) — 구현 보류

Discord Webhook 연동을 포함한 알림 규칙(Pod CrashLoopBackOff, Node NotReady, CPU/메모리
임계치, PVC 사용량 임계치, GPU, PostgreSQL, Tailscale, Backup 등 팀 문서에 정리된 후보
기준들) 구현은 이번 스프린트에서는 진행하지 않고 보류한다. 지금 온프레미스 테스트
클러스터에는 GPU/PostgreSQL(KT Cloud)/Tailscale/Backup 등 후보 기준에 해당하는 컴포넌트
자체가 아직 없어서 일부만 먼저 구현하면 다른 파트가 붙는 시점에 다시 설계해야 하는
이중 작업이 발생한다. 따라서 **AWS EKS로 이전하고 다른 파트(백엔드/AI/보안 등)와의
연동이 붙는 시점에, 그때 존재하는 컴포넌트 전체를 기준으로 알림 규칙을 한 번에
설계·구현**하기로 결정함. 구현 방식은 팀 합의대로 Prometheus Alertmanager가 아니라
**Grafana Alerting → Discord Webhook** (Grafana 자체 Unified Alerting 기능, secret은
`moongcheap-develop-infra-discord-secret` 사용 예정)으로 진행한다.

---

## 9. Service `LoadBalancer` → `ClusterIP` 전환

### 배경

CI/CD 파이프라인 정합성 점검(`2026-09-16 CI/CD 정상 동작을 위한 수정·추가 총정리` §4-2)에서
모니터링 스택의 Service들이 전부 `type: LoadBalancer`로 되어 있는 점이 지적됨. 설계서
3.2절의 "AWS Load Balancer 사용하지 않음" 원칙 위반이며, AWS EKS 기준으로는 서브넷에
`kubernetes.io/role/elb` 태그가 없어 CLB 생성이 실패하거나(추정), 생성되더라도 CLB
5개 = 월 약 $90 비용 발생 + Prometheus/Loki가 인터넷에 그대로 노출되는 문제가 있음.
7절에 정리된 "도메인 연결 후 Ingress 전환" 계획과 별개로, ClusterIP 전환 자체는 비용·보안
문제라 먼저 처리하기로 함.

### 대상 파일

| 파일 | 필드 | 변경 |
| --- | --- | --- |
| `gitops/platform/monitoring/kube-prometheus-stack/values.yaml` | `prometheus.service.type` | `LoadBalancer` → `ClusterIP` |
| `gitops/platform/monitoring/kube-prometheus-stack/values.yaml` | `grafana.service.type` | `LoadBalancer` → `ClusterIP` |
| `gitops/platform/monitoring/loki/values.yaml` | `gateway.service.type` | `LoadBalancer` → `ClusterIP` |
| `gitops/platform/observability/alloy-metrics/values.yaml` | `service.type` (top-level) | `LoadBalancer` → `ClusterIP` |
| `gitops/platform/observability/alloy-logs/values.yaml` | `service.type` (top-level) | `LoadBalancer` → `ClusterIP` |

```yaml
# kube-prometheus-stack/values.yaml
prometheus:
  service:
    type: ClusterIP
grafana:
  service:
    type: ClusterIP
```

```yaml
# loki/values.yaml
gateway:
  service:
    type: ClusterIP
```

```yaml
# alloy-metrics/values.yaml, alloy-logs/values.yaml
service:
  type: ClusterIP
```

### 주의 — 접근 경로 단절

`ingress-nginx`/`cloudflared`가 아직 리포에 구성되어 있지 않음(CI/CD 점검 §4-3). 즉 이
전환을 적용하는 즉시, 지금까지 쓰던 사설 IP 기반 접근 경로(예: Grafana `172.16.8.33`)가
끊긴다. Ingress 전환(7절)이 완료되기 전까지는 아래처럼 `kubectl port-forward`로
임시 접근한다.

```shell
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
kubectl port-forward -n monitoring svc/loki-gateway 3100:80
```

정식 접근 경로 복구는 7절의 Ingress 작업(ingress-nginx + cloudflared 배포, Grafana/Prometheus
`ingress.enabled: true` 설정)이 끝난 뒤로 예정한다.