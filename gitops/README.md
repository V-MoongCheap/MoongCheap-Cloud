# MoongCheap GitOps

MoongCheap의 Kubernetes 배포 설정과 ArgoCD 기반 GitOps 구성을 관리한다.

Frontend / Backend / AI 애플리케이션 코드는 각 서비스 Repository에서 관리한다.

이 Repository의 `gitops/`에서는 **Helm Chart, Values, ArgoCD ApplicationSet, Kubernetes Platform 구성**을 관리한다.

GitOps 구조는 다음 기준으로 가져간다.

> **ApplicationSet + 공통 Helm Chart + Values Layering + Service / Platform 분리**

---

## 1. Structure

```text
MoongCheap-Cloud/
└── gitops/
    ├── charts/
    │   └── moongcheap-service/
    │       ├── Chart.yaml
    │       ├── values.yaml
    │       └── templates/
    │           ├── _helpers.tpl
    │           ├── deployment.yaml
    │           ├── service.yaml
    │           ├── ingress.yaml
    │           ├── hpa.yaml
    │           └── pdb.yaml
    │
    ├── values/
    │   ├── base.yaml
    │   ├── env/
    │   │   ├── dev.yaml
    │   │   └── prod.yaml
    │   ├── services/
    │   │   ├── frontend.yaml
    │   │   ├── backend.yaml
    │   │   └── ai.yaml
    │   └── overrides/
    │       ├── dev/
    │       │   ├── frontend.yaml
    │       │   ├── backend.yaml
    │       │   └── ai.yaml
    │       └── prod/
    │           ├── frontend.yaml
    │           ├── backend.yaml
    │           └── ai.yaml
    │
    ├── platform/
    │   ├── namespaces/
    │   │   ├── dev.yaml
    │   │   └── prod.yaml
    │   │
    │   ├── monitoring/
    │   │   └── kube-prometheus-stack/
    │   │       ├── config.yaml
    │   │       └── values.yaml
    │   │
    │   ├── ingress/
    │   ├── observability/
    │   ├── autoscaling/
    │   ├── rollouts/
    │   ├── jenkins/
    │   ├── secrets/
    │   ├── policies/
    │   └── storage/
    │
    ├── argocd/
    │   ├── projects/
    │   │   ├── services-project.yaml
    │   │   └── platform-project.yaml
    │   │
    │   ├── applicationset-services-dev.yaml
    │   ├── applicationset-services-prod.yaml
    │   └── applicationset-platform.yaml
    │
    └── README.md
```

현재 사용하지 않는 Platform 구성은 필요할 때 순차적으로 추가한다.

---

## 2. Directory

| 경로 | 역할 |
| --- | --- |
| `charts/` | Frontend / Backend / AI 공통 Helm Chart |
| `values/` | 환경별 / 서비스별 Helm 설정 |
| `platform/` | EKS 클러스터 공통 Platform 구성 |
| `argocd/projects/` | Service / Platform 배포 권한 관리 |
| `argocd/applicationset-*` | ArgoCD Application 자동 생성 |

---

## 3. Helm & Values

Frontend / Backend / AI는 `moongcheap-service` 공통 Helm Chart를 사용한다.

서비스와 환경별 차이는 Values로 관리한다.

```text
charts/moongcheap-service/values.yaml
                ↓
values/base.yaml
                ↓
values/env/<environment>.yaml
                ↓
values/services/<service>.yaml
                ↓
values/overrides/<environment>/<service>.yaml
```

각 Values 역할은 다음과 같다.

```text
base
→ 전체 서비스 공통 설정

env
→ dev / prod 환경 설정

services
→ frontend / backend / ai 서비스 설정

overrides
→ 특정 환경 + 특정 서비스의 최종 설정
```

예를 들어 `backend-dev`는 다음 Values를 조합한다.

```text
base.yaml
+
env/dev.yaml
+
services/backend.yaml
+
overrides/dev/backend.yaml
```

Jenkins에서 새로운 이미지를 ECR에 Push한 뒤 배포 Image Tag를 변경할 경우
`overrides/<environment>/<service>.yaml`을 변경하는 방식으로 연결한다.

---

## 4. Service 배포

서비스는 하나의 EKS 클러스터 안에서 Namespace를 기준으로 dev / prod 환경을 분리한다.

```text
EKS
├── moongcheap-dev
│   ├── frontend
│   ├── backend
│   └── ai
│
└── moongcheap-prod
    ├── frontend
    ├── backend
    └── ai
```

ArgoCD ApplicationSet도 환경별로 분리한다.

```text
applicationset-services-dev.yaml
applicationset-services-prod.yaml
```

### Dev

```text
develop
   ↓
applicationset-services-dev
   ↓
moongcheap-dev
```

### Prod

```text
main
   ↓
applicationset-services-prod
   ↓
moongcheap-prod
```

---

## 5. Platform

Platform은 dev / prod로 중복 설치하지 않는다.

하나의 EKS 클러스터에서 공통으로 사용하는 구성은 `platform/`에서 한 세트만 관리한다.

예:

```text
EKS
├── moongcheap-dev
├── moongcheap-prod
│
├── monitoring
├── observability
├── jenkins
├── keda
└── argo-rollouts
```

Platform 구성은 다음 형태로 관리한다.

```text
<platform>/
├── config.yaml
└── values.yaml
```

예:

```text
platform/
└── monitoring/
    └── kube-prometheus-stack/
        ├── config.yaml
        └── values.yaml
```

`config.yaml`에는 Helm Chart 정보를 작성한다.

```yaml
name: kube-prometheus-stack
namespace: monitoring

helm:
  repoURL: https://prometheus-community.github.io/helm-charts
  chart: kube-prometheus-stack
  version: REPLACE_ME
```

`values.yaml`에는 MoongCheap 환경에서 사용할 Helm 설정을 작성한다.

---

## 6. Platform 자동 탐색

Platform ApplicationSet은 Git File Generator를 사용한다.

```text
gitops/platform/**/config.yaml
```

경로의 `config.yaml`을 자동으로 탐색한다.

예를 들어:

```text
platform/
└── monitoring/
    └── kube-prometheus-stack/
        ├── config.yaml
        └── values.yaml
```

이 추가되면 ApplicationSet이 다음 값을 읽는다.

```text
name
namespace
helm.repoURL
helm.chart
helm.version
```

그리고 같은 디렉터리의:

```text
values.yaml
```

을 자동으로 사용한다.

새로운 Platform을 추가할 때 `applicationset-platform.yaml`을 직접 수정할 필요는 없다.

Platform 디렉터리에:

```text
config.yaml
values.yaml
```

을 추가하면 ApplicationSet이 자동으로 탐색한다.

---

## 7. ArgoCD Project

Service와 Platform은 서로 다른 AppProject를 사용한다.

```text
argocd/projects/
├── services-project.yaml
└── platform-project.yaml
```

### Service Project

```text
moongcheap-services
```

Frontend / Backend / AI Application을 관리한다.

배포 대상은:

```text
moongcheap-dev
moongcheap-prod
```

Namespace로 제한한다.

Service ApplicationSet은:

```yaml
project: moongcheap-services
```

를 사용한다.

### Platform Project

```text
moongcheap-platform
```

Prometheus / Grafana / Loki / Alloy / Jenkins 등 클러스터 공통 Platform을 관리한다.

Platform에서 사용하는 Git Repository와 외부 Helm Repository를 허용한다.

Platform ApplicationSet은:

```yaml
project: moongcheap-platform
```

을 사용한다.

---

## 8. ApplicationSet

현재 ApplicationSet은 세 개로 구성한다.

```text
argocd/
├── applicationset-services-dev.yaml
├── applicationset-services-prod.yaml
└── applicationset-platform.yaml
```

### Service Dev

```text
applicationset-services-dev
        │
        ├── moongcheap-frontend-dev
        ├── moongcheap-backend-dev
        └── moongcheap-ai-dev
```

### Service Prod

```text
applicationset-services-prod
        │
        ├── moongcheap-frontend-prod
        ├── moongcheap-backend-prod
        └── moongcheap-ai-prod
```

### Platform

Platform은 클러스터 공통으로 한 세트만 생성한다.

```text
applicationset-platform
        │
        └── kube-prometheus-stack
```

향후 Loki, Alloy, Jenkins, KEDA 등을 추가하면 해당 디렉터리의 `config.yaml`을 자동으로 탐색하여 Application을 생성한다.

---

## 9. Deployment Flow

### Application

```text
Application Repository
        ↓
      Jenkins
        ↓
   Build / Test
        ↓
 Docker Image Build
        ↓
      ECR Push
        ↓
GitOps Image Tag 변경
        ↓
Service ApplicationSet
        ↓
      ArgoCD
        ↓
       EKS
        ↓
moongcheap-dev / moongcheap-prod
```

### Platform

```text
config.yaml
    +
values.yaml
    ↓
Platform ApplicationSet
    ↓
   ArgoCD
    ↓
    EKS
    ↓
Platform Namespace
```

---

## 10. 관리 기준

- Application 공통 Kubernetes 리소스는 `charts/`에서 관리
- 환경 / 서비스별 설정은 `values/`에서 관리
- 서비스는 `dev / prod` Namespace로 분리
- Platform은 클러스터 공통으로 한 세트만 운영
- Platform 설정은 `config.yaml + values.yaml` 형태로 관리
- Service와 Platform은 별도의 AppProject 사용
- Service와 Platform은 별도의 ApplicationSet 사용
- Platform은 `config.yaml` 기반으로 자동 탐색
- 실제 Secret 값은 Git에 저장하지 않음
- Application Source Code는 각 서비스 Repository에서 관리
- GitOps Repository에는 배포 상태와 Platform 설정을 관리
- ArgoCD가 Git 선언 상태와 EKS 상태를 동기화

---

## 11. 전체 흐름

```text
                              EKS
                               │
           ┌───────────────────┼────────────────────┐
           │                   │                    │
   moongcheap-dev      moongcheap-prod         Platform
           │                   │                    │
      FE / BE / AI        FE / BE / AI        monitoring
           │                   │              observability
           │                   │                 jenkins
           │                   │                   ...
           │                   │                    │
           └──────────────┬────┘                    │
                          │                         │
              Service ApplicationSet      Platform ApplicationSet
                          │                         │
                          ↓                         ↓
                 moongcheap-services       moongcheap-platform
                    AppProject                AppProject
                          │                         │
                          └────────────┬────────────┘
                                       ↓
                                     ArgoCD
```