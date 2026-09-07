## 1. 문서 목적

본 문서는 클라우드 인프라 파트에서 Terraform, Kubernetes, Helm, ArgoCD, Jenkins, Observability 등의 코드를 공동 관리하기 위한 Git 협업 규칙과 Repository / Directory 작성 기준을 정의한다.

주요 목적은 다음과 같다.

- 여러 팀원의 동시 작업 시 코드 충돌 최소화
- 인프라 변경 이력 추적
- PR 기반 코드 리뷰 및 변경 검증
- 담당 영역별 코드 관리 기준 통일
- Terraform IaC 및 ArgoCD GitOps의 재현성 확보
- 잘못된 인프라 변경이 실제 환경에 직접 반영되는 상황 방지

---

# 2. Branch 전략

## 2.1 Branch 구조

```
main
 │
 ├── develop
 │    ├── feat/*
 │    ├── fix/*
 │    ├── refactor/*
 │    ├── docs/*
 │    ├── test/*
 │    └── chore/*
 │
 └── hotfix/*
```

일반적인 개발은 `develop`를 기준으로 수행하고, 현재 `main` 기준 배포 상태를 긴급하게 수정해야 하는 경우에만 `hotfix/*`를 사용한다.

---

## 2.2 main

최종적으로 검증된 안정 상태를 관리한다.

- Demo / Production 배포 기준 Branch
- 직접 Push 금지
- 반드시 Pull Request를 통해 Merge
- CI 검증을 통과한 코드만 Merge
- Force Push 및 Branch 삭제 금지
- 언제든 배포 가능한 상태 유지

---

## 2.3 develop

클라우드 인프라 파트의 통합 개발 Branch이다.

- 일반 작업 Branch의 기본 Merge 대상
- 직접 Push 금지
- PR + CI + Review 이후 Merge
- 개발 환경 기준의 통합 상태 유지

일반적인 작업 흐름:

```
develop
 ↓
feat/* · fix/* · refactor/*
 ↓
작업 및 검증
 ↓
PR
 ↓
develop
 ↓
통합 검증
 ↓
PR
 ↓
main
```

---

## 2.4 hotfix

현재 `main` 기준으로 배포된 환경에서 즉시 수정해야 하는 문제가 발생했을 때 사용한다.

`hotfix/*`는 `develop`가 아닌 **`main`에서 분기한다.**

```
main
 ↓
hotfix/*
 ↓
수정
 ↓
CI / Review
 ↓
PR
 ↓
main
 ↓
배포
```

Hotfix 완료 후 변경사항을 반드시 `develop`에도 동기화한다.

```
hotfix/* → main
             │
             └────→ develop 동기화
```

이를 통해 이후 `develop → main` Merge 과정에서 Hotfix가 누락되거나 충돌하는 것을 방지한다.

### fix와 hotfix의 차이

| Branch | 분기 | Merge | 용도 |
| --- | --- | --- | --- |
| `fix/*` | `develop` | `develop` | 개발 과정에서 발견된 일반 오류 |
| `hotfix/*` | `main` | `main` + `develop` 동기화 | 현재 배포 버전의 긴급 수정 |

---

# 3. Branch Naming Convention

작업 Branch는 다음 형식을 사용한다.

```
<type>/<작업-내용>
```

| Type | 용도 |
| --- | --- |
| `feat` | 신규 기능·리소스 추가 |
| `fix` | 개발 중 오류 수정 |
| `refactor` | 기능 변화 없는 구조 개선 |
| `docs` | 문서 변경 |
| `test` | 테스트 및 검증 |
| `chore` | 설정·버전 등 관리 작업 |
| `hotfix` | 배포 상태의 긴급 수정 |

예:

```
feat/terraform-vpc
feat/eks-nodegroup
feat/helm-backend

fix/nat-routing
fix/argocd-path

refactor/vpc-module
docs/terraform-guide
test/jenkins-pipeline

hotfix/argocd-sync
```

Branch 이름은 영문 소문자를 사용하며 단어는 `-`로 구분한다.

---

# 4. Commit Convention

Conventional Commits 형식을 기반으로 한다.

```
<type>(<scope>): <description>
```

예:

```
feat(vpc): add private subnet
feat(eks): add managed node group
feat(helm): add backend chart

fix(nat): fix private subnet route
fix(argocd): fix application path

refactor(vpc): separate routing module

docs(terraform): add execution guide

ci(jenkins): add terraform validation
```

### Commit Type

| Type | 의미 |
| --- | --- |
| `feat` | 신규 기능·리소스 |
| `fix` | 오류 수정 |
| `refactor` | 구조 개선 |
| `docs` | 문서 변경 |
| `test` | 테스트 |
| `chore` | 기타 관리 |
| `ci` | CI 설정 |
| `build` | Build 관련 변경 |
| `revert` | 이전 변경 복구 |

Scope는 변경 영역을 기준으로 작성한다.

```
vpc
eks
ecr
iam
s3
nat
terraform
helm
argocd
jenkins
monitoring
backup
ktcloud
```

하나의 Commit에는 가능한 하나의 논리적 변경만 포함한다.

---

# 5. Pull Request Convention

`develop`, `main` 변경은 반드시 Pull Request를 통해 진행한다.

PR 제목은 Commit Convention과 동일한 형식을 권장한다.

```
feat(vpc): add network infrastructure
fix(eks): fix node group configuration
hotfix(argocd): fix sync configuration
```

### PR Template

```markdown
## 작업 내용

- 주요 변경 사항

## 변경 이유

- 해당 변경이 필요한 이유

## 영향 범위

- [ ] AWS Infrastructure
- [ ] Terraform
- [ ] Kubernetes / Helm
- [ ] CI/CD
- [ ] Observability
- [ ] KT Cloud
- [ ] Application Deployment

## 검증

- [ ] Local Validation 완료
- [ ] CI 통과
- [ ] 관련 문서 수정

## 참고 사항

- 리뷰어가 확인해야 할 사항
```

Terraform 변경 시:

```
terraform fmt
terraform validate
terraform plan
```

Helm 변경 시:

```
helm lint
helm template
```

---

# 6. Review / Merge 규칙

`develop`, `main` Merge 전 최소 1명 이상의 Review를 받는 것을 기본으로 한다.

가능하면 해당 변경 영역 담당자가 Review한다.

```
Terraform / AWS
→ Infrastructure 담당

Kubernetes / Helm / ArgoCD
→ Kubernetes / GitOps 담당

Jenkins
→ CI/CD 담당

Prometheus / Loki / Grafana
→ Observability 담당
```

파트장이 모든 PR을 직접 승인하는 중앙집중형 방식은 지양한다.

기본 Merge 방식은 **Squash Merge**를 사용한다.

```
feat(vpc): add subnet
fix(vpc): fix cidr
fix(vpc): fix route

        ↓ Squash

feat(vpc): add vpc network infrastructure
```

Merge 완료 후 작업 Branch는 삭제한다.

---

# 7. Branch Protection

### main

```
Require Pull Request
Require 1 Approval
Require Status Checks
Require Conversation Resolution

Block Force Push
Block Branch Deletion
```

### develop

```
Require Pull Request
Require 1 Approval
Require Status Checks

Block Force Push
```

---

# 8. Repository / Directory 구조

```
infra-repository/
│
├── terraform/
├── helm/
├── argocd/
├── jenkins/
├── observability/
├── scripts/
├── docs/
│
├── .github/
│   ├── CODEOWNERS
│   └── pull_request_template.md
│
├── .gitignore
└── README.md
```

---

# 9. Terraform Directory

Terraform은 재사용 가능한 Module과 환경별 Root Module을 분리한다.

```
terraform/
├── modules/
│   ├── vpc/
│   ├── eks/
│   ├── ecr/
│   ├── iam/
│   ├── s3/
│   └── nat/
│
└── envs/
    ├── develop/
    │   ├── backend.tf
    │   ├── providers.tf
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars.example
    │
    └── prod/
        └── ...
```

Module 기본 구조:

```
modules/vpc/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md
```

---

# 10. Helm Directory

```
helm/
├── frontend/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-develop.yaml
│   └── templates/
│
├── backend/
│   └── ...
│
└── ai/
    └── ...
```

환경 차이는 Manifest를 복제하기보다 Values를 통해 관리한다.

Secret 값은 Values에 직접 저장하지 않는다.

---

# 11. ArgoCD Directory

```
argocd/
├── develop/
│   ├── frontend.yaml
│   ├── backend.yaml
│   ├── ai.yaml
│   └── observability.yaml
│
└── prod/
    └── ...
```

GitOps 변경 흐름:

```
Git 변경
   ↓
PR / Review
   ↓
Merge
   ↓
ArgoCD Sync
   ↓
EKS
```

Rollback은 Git 변경 이력이 남도록 다음 방식을 기본으로 한다.

```
문제 발생
   ↓
Git revert
   ↓
ArgoCD Sync
   ↓
이전 Desired State 복구
```

---

# 12. Jenkins / Observability Directory

```
jenkins/
├── Jenkinsfile
├── pipelines/
└── scripts/
```

```
observability/
├── prometheus/
├── grafana/
│   └── dashboards/
├── loki/
└── alloy/
```

Pipeline, Dashboard, Alert Rule 등의 설정도 가능한 Git에서 코드로 관리한다.

---

# 13. CODEOWNERS

변경 영역에 따라 자동으로 Reviewer를 지정할 수 있도록 CODEOWNERS 사용을 권장한다.

```
/terraform/       @terraform-owner
/helm/            @kubernetes-owner
/argocd/          @kubernetes-owner
/jenkins/         @cicd-owner
/observability/   @observability-owner
```

실제 GitHub 사용자 또는 Team 이름으로 변경하여 사용한다.

---

# 14. Git 제외 대상

다음 정보는 Repository에 Commit하지 않는다.

```
*.tfstate
*.tfstate.*
.terraform/

*.tfvars
!*.tfvars.example

.env
.env.*

*.pem
*.key

kubeconfig
credentials

AWS Access Key
AWS Secret Access Key

DB Password
API Token
Webhook Secret
```

---

# 15. Cloud Infra 작업 Workflow

### 일반 변경

```
Issue / 작업 할당
        ↓
develop 최신화
        ↓
작업 Branch 생성
        ↓
코드 작성
        ↓
Local Validation
        ↓
Commit / Push
        ↓
Pull Request
        ↓
CI Validation
        ↓
Code Review
        ↓
develop Merge
        ↓
개발 환경 검증
        ↓
develop → main PR
        ↓
main Merge
```

### 긴급 변경

```
운영/Demo 장애
       ↓
main에서 hotfix/* 생성
       ↓
수정
       ↓
CI / Review
       ↓
main PR
       ↓
main Merge / 배포
       ↓
develop 동기화
```

---

# 16. 핵심 협업 원칙

1. `main`, `develop` 직접 Push 금지
2. 일반 작업은 `develop`에서 분기
3. 긴급 수정은 `main → hotfix/*`
4. Hotfix 완료 후 반드시 `develop` 동기화
5. 하나의 Branch에는 하나의 작업 목적
6. 작은 PR 지향
7. 최소 1인 Review
8. Secret Commit 금지
9. 변경 이유와 영향 범위를 PR에 기록
10. 코드와 관련 문서를 함께 최신화

> **작업 Branch에서 변경하고 PR에서 검증하며, Git에 기록된 상태를 기준으로 Infrastructure와 Kubernetes 환경을 관리한다.**
