# 네이밍 규약서 (Terraform / Helm chart 등) + 환경/변수/Secret 관리

### 1. 문서 개요

본 문서는 뭉치(MoongCheap) 프로젝트의 AWS EKS / Terraform / Helm / ArgoCD 인프라에서 사용할 리소스 네이밍 규칙, 환경 구분, 환경변수·Secret 관리 방식을 정의한다. 다른 인프라 문서(`클라우드 인프라 아키텍처 설계서` 등)에서 "디렉토리 구조·모듈 구성·State 관리 방식은 본 문서를 따른다"고 명시하고 있어, 본 문서가 관련 컨벤션의 기준 문서 역할을 한다.

### 2. 공통 네이밍 원칙

```
{project}-{env}-{service}-{resource}
```

- `project` = `moongcheap`
- `env` = `develop` | `prod` (확정 — Branch Convention, 비용 태그 표준 등 다수 최신 문서에서 일관되게 사용)
- `service` = `fe` | `be` | `ai` | `infra`
- `resource` = 리소스 종류 약어 (vpc, nat, eks 등)

### 3. Terraform 리소스 네이밍 및 디렉토리 구조

| 리소스 네이밍 규칙 예시 | | |
| --- | --- | --- |
| VPC | `{project}-{env}-vpc` | `moongcheap-develop-vpc` |
| Subnet | `{project}-{env}-{public\|private}-subnet-{az}` | |
| NAT Instance | `{project}-{env}-nat` | `moongcheap-develop-nat` (t3a.micro) |
| EKS Cluster | `{project}-{env}-eks` | `moongcheap-prod-eks` |
| Node Pool | `{project}-{env}-cpu-pool` / `{project}-{env}-gpu-pool` | GPU Pool은 taint `gpu=true:NoSchedule` |
| Karpenter NodePool | `{project}-{env}-gpu-karpenter` | 적용 여부 자체가 [협의중] (서비스 구성 후 결정) |
| IAM Role/IRSA | `{project}-{env}-{service}-role` | `moongcheap-prod-be-role` |
| ECR Repository | `moongcheap/{service}` | `moongcheap/backend` |
| S3 Bucket (백업) | `{project}-{env}-backup` | KT Cloud DB dump 저장용 |
| Terraform State | 단일 버킷 `moongcheap-tfstate`, key = `{env}/terraform.tfstate` | |

디렉토리 구조 (Git 협업 Convention 기준):

```
terraform/
├── modules/
│   ├── vpc/
│   ├── eks/
│   ├── ecr/
│   ├── iam/
│   ├── s3/
│   └── nat/
└── envs/
    ├── develop/
    │   ├── backend.tf
    │   ├── providers.tf
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars.example
    └── prod/
        └── (develop와 동일 구성)
```

> KT Cloud 쪽 리소스(PostgreSQL VM 등)는 Terraform이 아니라 Ansible로 초기 세팅하는 범위에 속한다 (K8s 외부 영역 한정 원칙). 네이밍은 동일 원칙(`{project}-{env}-...`)을 따르되, 실제 구성은 KT Cloud 조사 문서(준우) 결과에 따라 확정.

### 4. Helm / K8s 네이밍 및 디렉토리 구조

- Namespace: `be`, `fe`, `ai`, `infra`
- Release: `{service}-{env}`
- Chart 디렉토리: `charts/{service}/`
- Values 파일: `values-{env}.yaml`
- K8s Object: `{service}-{object종류}` (예: `be-deployment`, `ai-llm-service`)
- GPU taint: `gpu=true:NoSchedule`
- KEDA ScaledObject: `{service}-scaledobject` — 적용 여부/정책 [협의중] (LLM Pod scale-to-zero 방향만 원칙 확정, 세부 미정)
- AI Pod 구성: 현재 가장 최신 아키텍처 기준으로는 **LLM Pod 1개(Qwen3-14B-AWQ, vLLM)로 단순화**된 상태. 다만 이전 버전 문서에는 2-LLM(14B+8B)+Cluster Matcher 구성도 남아있어, AI팀에 현재 유효한 구성이 맞는지 재확인 권장.

디렉토리 구조:

```
helm/
├── frontend/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-develop.yaml
│   ├── values-prod.yaml
│   └── templates/
├── backend/
│   └── (동일 구성)
└── ai/
    └── (동일 구성)
```

### 5. ArgoCD 디렉토리 구조 및 GitOps 저장소 구조

- **저장소 구조 (확정)**: FE/BE/AI는 각자 독립된 Application Repository를 유지(내부 커밋/디렉토리 컨벤션은 각 팀 자율), 인프라팀은 단일 모노레포 `infra-repository/`를 운영 (`terraform/`, `helm/`, `argocd/`, `jenkins/`, `observability/`, `scripts/`, `docs/`, `.github/`).
- Rollback 원칙: ArgoCD 자체 Rollback UI보다 **Git revert → ArgoCD Auto Sync**를 기본 절차로 한다 (GitOps 원칙상 변경 이력이 Git에 남아야 함).

```
argocd/
├── develop/
│   ├── frontend.yaml
│   ├── backend.yaml
│   ├── ai.yaml
│   └── observability.yaml
└── prod/
    └── (동일 구성)
```

CI/CD 흐름: `GitHub → Jenkins(K8s Dynamic Agent, Build/Test) → Docker Image Build → ECR Push → GitOps Repo 갱신(Image Tag/Helm Values) → ArgoCD Sync → EKS`

### 6. 컨테이너 이미지 네이밍

- 태그: `{env}-{git-short-sha}` (예: `develop-a1b2c3d`)
- `latest` 태그 사용 금지
- ECR: `moongcheap/{service}:{env}-{git-short-sha}`

### 7. 환경 구분

| 환경 용도 배포 브랜치 | | |
| --- | --- | --- |
| `develop` | 개발 통합 환경 | `develop` 브랜치 Merge 시 |
| `prod` | 최종 검증 / Demo 배포 | `main` 브랜치 Merge 시 |

`hotfix/*` 브랜치는 긴급 수정 후 `main`에 병합 + `develop`에도 동기화.

### 8. 변수 관리

- Terraform: `envs/{env}/terraform.tfvars` (`.tfvars.example`만 커밋, 실제 값은 gitignore)
- Helm: `values-{env}.yaml`
- Application 환경변수 (확정, CI/CD Git 가이드 기준):

```
DB_URL
DB_USERNAME
DB_PASSWORD
AI_API_URL
REDIS_HOST
```

> ⚠️ **[협의중] DB 인스턴스 구성에 따라 변수가 추가될 수 있음.** 현재 팀 내부 문서 간 불일치가 있음 (아래 참고):
>
> - **옵션 A (단일 인스턴스)**: Backend와 AI가 동일 PostgreSQL(+pgvector 확장)을 공유, 스키마로 논리 분리 → `DB_URL` 하나로 충분
> - **옵션 B (분리 인스턴스)**: Backend용 PostgreSQL과 AI Vector DB(pgvector)를 별도 인스턴스로 구성 → `DB_URL`(BE용) + AI 쪽 별도 변수(가칭 `AI_VECTOR_DB_URL`, 아직 팀 내 명명된 바 없음) 필요
>
> → 확정 전까지 최종 변수명 확정 불가. 우선순위 높은 확인 필요 항목.

- Redis/OpenSearch 도입 여부·방식 자체가 [협의중] (BE팀 "여유 있으면 도입" 조건부 요청) → 확정 시 `REDIS_HOST`(이미 반영됨), OpenSearch는 변수명 미정.

### 9. Secret 관리

- 원칙: 코드/이미지에 하드코딩 금지, Secret Manager류 사용 (보안팀 요구사항, 아키텍처에는 이미 반영된 상태)
- **[협의중] 구체적 도구(AWS Secrets Manager vs SSM Parameter Store)는 오늘(8/25) 멘토링 시점까지도 미정으로 재확인됨.**
- 흐름(안): Secrets Manager/Parameter Store → External Secrets Operator → K8s Secret → Pod
- Naming: `{service}-{용도}-secret` (예: `be-db-secret`)
- `.gitignore` 필수 제외 대상: `.tfstate`, `.tfstate.*`, `.terraform/`, `.tfvars`(`!*.tfvars.example` 예외), `.env`, `.env.*`, `.pem`, `.key`, `kubeconfig`, `credentials`, AWS Access/Secret Key, DB Password, API Token, Webhook Secret

### 부록: 미확정 사항 정리 (제출 전 확인 권장 우선순위 순)

1. **[최우선] DB 인스턴스 구성 — 단일 vs 분리**: 팀 문서 간 실제 불일치 존재 (본문 참고). Secret/환경변수 네이밍에 직접 영향.
2. KT Cloud PostgreSQL의 pgvector 확장 지원 여부 — 준우님 조사 진행 중, 미확인 시 VM 직접 설치로 폴백
3. Secret Store 최종 도구 (Secrets Manager vs Parameter Store)
4. Redis/OpenSearch 도입 여부 및 방식
5. KEDA/Karpenter/HPA 적용 대상 및 세부 정책 (서비스 구성 후 결정 예정)
6. GPU/CPU 인스턴스 타입 (g4dn.xlarge/m7i.large는 AI팀 제안이자 현재 비용산정용 가정치, 인프라 차원 확정 아님 — 오늘 멘토링에서 BE 쪽 인스턴스 사이즈 재조율 필요성도 제기됨)
7. Ingress 최종 대체 기술 (NGINX 유지 중, 추후 Gateway API 전환 검토 — Istio는 제외 방향)
