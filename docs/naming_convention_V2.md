# 네이밍 규약서 (Terraform / Helm Chart 등) + 환경/변수/Secret 관리

------------------------------------------------------------------------

## 1. 문서 개요

본 문서는 뭉치(MoongCheap) 프로젝트의 AWS EKS / Terraform / Helm /
ArgoCD 기반 인프라에서 사용할 **리소스 네이밍 규칙, 환경 구분,
Repository/Directory 구조, 환경변수 및 Secret 관리 방식**을 정의한다.

`클라우드 인프라 아키텍처 설계서`를 실제 Terraform / Helm / ArgoCD
코드로 구현할 때 본 문서를 Naming 및 Directory Convention의 기준 문서로
사용한다.

현재 인프라 구성은 다음을 기준으로 한다.

-   **AWS**: Primary Service Cloud
-   **KT Cloud**: Terraform 관리 환경 + Secondary Backup Storage
-   **EKS**: 단일 Cluster
-   **Worker Node Group**
    -   FE Worker
    -   BE·AI Worker
-   **Data**
    -   Amazon RDS for PostgreSQL + pgvector
    -   Amazon S3
    -   Amazon ElastiCache Redis
    -   Amazon OpenSearch Service
-   **CI/CD**
    -   Jenkins
    -   Amazon ECR
    -   ArgoCD
-   **Observability**
    -   Prometheus
    -   Grafana Alloy
    -   Loki
    -   Grafana

GPU Node 및 기존 AWS ↔ KT Cloud Tailscale Site-to-Site 구조는 사용하지
않는다.

------------------------------------------------------------------------

## 2. 공통 네이밍 원칙

AWS Infrastructure Resource는 다음 형식을 기본으로 한다.

``` text
{project}-{env}-{service}-{resource}
```

-   `project` = `moongcheap`
-   `env` = `develop` \| `prod`
-   `service` = `fe` \| `be` \| `ai` \| `infra`
-   `resource` = Resource 종류 또는 역할

특정 Application Service에 속하지 않는 공통 Infrastructure Resource는
`service`를 생략할 수 있다.

예:

``` text
moongcheap-develop-vpc
moongcheap-develop-eks
moongcheap-develop-nat
moongcheap-develop-be-role
```

### 기본 원칙

-   영문 소문자를 기본으로 한다.
-   단어 구분은 `-`를 사용한다.
-   Environment 이름은 `develop`, `prod`로 통일한다.
-   AWS Resource Name/Tag와 Terraform 내부 Resource Identifier를
    구분한다.
-   Terraform 내부 Identifier에서는 `-` 대신 `_`를 사용한다.

예:

``` hcl
resource "aws_vpc" "main" {
  tags = {
    Name = "moongcheap-develop-vpc"
  }
}
```

------------------------------------------------------------------------

## 3. Terraform Resource Naming

### 3.1 Network

  Resource             Naming
  -------------------- --------------------------------
  VPC                  `moongcheap-{env}-vpc`
  Internet Gateway     `moongcheap-{env}-igw`
  Public Subnet        `moongcheap-{env}-public-{az}`
  WEB Private Subnet   `moongcheap-{env}-web-{az}`
  WAS Private Subnet   `moongcheap-{env}-was-{az}`
  DB Private Subnet    `moongcheap-{env}-db-{az}`
  Public Route Table   `moongcheap-{env}-public-rt`
  WEB Route Table      `moongcheap-{env}-web-rt`
  WAS Route Table      `moongcheap-{env}-was-rt`
  DB Route Table       `moongcheap-{env}-db-rt`
  NAT Instance         `moongcheap-{env}-nat`
  NAT Elastic IP       `moongcheap-{env}-nat-eip`

Subnet의 `{az}`에는 실제 Availability Zone을 사용한다.

예:

``` text
moongcheap-develop-web-ap-northeast-2a
moongcheap-develop-was-ap-northeast-2a
moongcheap-develop-db-ap-northeast-2a
```

실제 AZ 및 CIDR은 아키텍처 설계서에서 확정한다.

### 3.2 Security Group

Security Group은 보호 대상 또는 역할을 기준으로 명명한다.

``` text
moongcheap-{env}-{target}-sg
```

  대상           Naming
  -------------- ----------------------------------
  NAT Instance   `moongcheap-{env}-nat-sg`
  FE Worker      `moongcheap-{env}-fe-sg`
  BE·AI Worker   `moongcheap-{env}-be-ai-sg`
  RDS            `moongcheap-{env}-rds-sg`
  Redis          `moongcheap-{env}-redis-sg`
  OpenSearch     `moongcheap-{env}-opensearch-sg`

Security Group Rule은 가능한 경우 CIDR 기반 허용보다 **Source Security
Group 기반 허용**을 우선한다.

### 3.3 EKS

  Resource                   Naming
  -------------------------- -----------------------------
  EKS Cluster                `moongcheap-{env}-eks`
  FE Managed Node Group      `moongcheap-{env}-fe-ng`
  BE·AI Managed Node Group   `moongcheap-{env}-be-ai-ng`
  FE Node Label              `workload=frontend`
  BE·AI Node Label           `workload=backend-ai`

기존 `cpu-pool`, `gpu-pool`, `gpu-karpenter` Naming은 폐기한다.

현재 Architecture에서는 GPU Node Group을 구성하지 않는다.

``` text
FE Node Group
→ WEB Private Subnet

BE·AI Node Group
→ WAS Private Subnet
```

Karpenter는 Scaling 정책 확정 전까지 별도 Resource Name을 정의하지
않는다.

### 3.4 IAM / IRSA

EKS Pod → AWS Resource 접근은 **IRSA**를 프로젝트 표준 방식으로
사용한다.

IAM Role:

``` text
moongcheap-{env}-{service-or-component}-role
```

IAM Policy:

``` text
moongcheap-{env}-{service-or-component}-{purpose}-policy
```

예:

``` text
moongcheap-develop-be-role
moongcheap-develop-ai-role
moongcheap-develop-ebs-csi-role
moongcheap-develop-jenkins-role

moongcheap-develop-be-s3-policy
moongcheap-develop-jenkins-ecr-policy
```

Workload별 IAM Role을 분리하고 최소 권한 원칙을 적용한다.

### 3.5 ECR

ECR Repository는 Environment별로 분리하지 않고 Service별 Repository를
사용한다.

  Service    Repository
  ---------- -----------------------
  Frontend   `moongcheap/frontend`
  Backend    `moongcheap/backend`
  AI         `moongcheap/ai`

Image Tag:

``` text
{env}-{git-short-sha}
```

예:

``` text
moongcheap/frontend:develop-a1b2c3d
moongcheap/backend:develop-d4e5f6a
moongcheap/ai:prod-123abcd
```

`latest` Tag는 사용하지 않는다.

### 3.6 RDS

| Resource | Naming |
| --- | --- |
| RDS Instance | `moongcheap-{env}-postgres` |
| DB Subnet Group | `moongcheap-{env}-db-subnet-group` |
| RDS Security Group | `moongcheap-{env}-rds-sg` |
| DB Secret | `moongcheap-{env}-db-secret` |

현재 Architecture 기준 RDS Spec:

``` text
Engine         = PostgreSQL
Instance Class = db.t4g.medium
Storage        = 50 GiB
Storage Type   = gp3
Multi-AZ       = Enabled
Public Access  = Disabled
Port           = 5432
pgvector       = PostgreSQL Extension
```

Database Name, Master Username, PostgreSQL Version 및 Backup/Deletion
정책은 아키텍처 설계서에서 별도로 확정한다.

### 3.7 S3

Application Primary Object Storage:

``` text
moongcheap-{env}-object
```

예:

``` text
moongcheap-develop-object
moongcheap-prod-object
```

Terraform State Bucket:

``` text
moongcheap-tfstate
```

State Key:

``` text
{env}/terraform.tfstate
```

예:

``` text
develop/terraform.tfstate
prod/terraform.tfstate
```

Application Object Storage와 Terraform State Bucket은 분리한다.

### 3.8 ElastiCache Redis

Redis는 현재 Architecture의 **확정 구성 요소**로 관리한다.

Naming:

``` text
moongcheap-{env}-redis
```

Security Group:

``` text
moongcheap-{env}-redis-sg
```

현재 Spec:

``` text
Engine   = Redis OSS
Instance = cache.t4g.small
Nodes    = 2
Pricing  = On-Demand
Port     = 6379
```

### 3.9 OpenSearch

OpenSearch는 현재 Architecture의 **확정 구성 요소**로 관리한다.

Naming:

``` text
moongcheap-{env}-opensearch
```

Security Group:

``` text
moongcheap-{env}-opensearch-sg
```

현재 Spec:

``` text
Instance = t3.small.search
Nodes    = 1
Storage  = gp3 10 GiB
IOPS     = 3000
Pricing  = On-Demand
Protocol = HTTPS 443
```

OpenSearch는 운영 로그 저장 용도가 아니라 **Application Search Engine**
용도로 사용한다. 운영 로그는 Alloy → Loki → Grafana 체계를 사용한다.

------------------------------------------------------------------------

## 4. Terraform Directory Structure

``` text
terraform/
├── modules/
│   ├── vpc/
│   ├── nat/
│   ├── eks/
│   ├── ecr/
│   ├── iam/
│   ├── rds/
│   ├── s3/
│   ├── secrets/
│   ├── elasticache/
│   └── opensearch/
│
└── envs/
    ├── develop/
    │   ├── backend.tf
    │   ├── providers.tf
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars.example
    └── prod/
        ├── backend.tf
        ├── providers.tf
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars.example
```

  Module          주요 관리 Resource
  --------------- -----------------------------------------
  `vpc`           VPC, Subnet, IGW, Route Table
  `nat`           NAT Instance, EIP, NAT Route
  `eks`           EKS Cluster, Managed Node Group, Add-on
  `ecr`           ECR Repository
  `iam`           IAM Role, IAM Policy, IRSA
  `rds`           RDS PostgreSQL, DB Subnet Group
  `s3`            Primary Object Storage
  `secrets`       AWS Secrets Manager Secret
  `elasticache`   ElastiCache Redis
  `opensearch`    OpenSearch Domain

Security Group은 해당 Resource를 소유하는 Module에서 관리하는 것을
기본으로 한다.

------------------------------------------------------------------------

## 5. Helm / Kubernetes Naming

### 5.1 Namespace

``` text
fe
be
ai
infra
```

  Namespace   Workload
  ----------- ----------------------------------------------------------
  `fe`        Frontend
  `be`        Backend
  `ai`        AI API / AI Workload
  `infra`     Jenkins / ArgoCD / Observability / Ingress / cloudflared

### 5.2 Helm Release

Application:

``` text
{service}-{env}
```

예:

``` text
fe-develop
be-develop
ai-develop
```

Infrastructure Component는 Component Name을 사용한다.

``` text
jenkins-develop
argocd-develop
prometheus-develop
loki-develop
grafana-develop
alloy-develop
```

### 5.3 Kubernetes Object

``` text
{service}-{object}
```

예:

``` text
fe-deployment
fe-service
be-deployment
be-service
ai-deployment
ai-service
be-hpa
ai-hpa
```

환경은 Helm Release Name(`{service}-{env}`)과 Values File로 구분하며,
Namespace는 환경별로 분리하지 않는다(8.1절 현재 배포 제약 참고). 따라서
Kubernetes Object Name에도 환경 식별자를 중복해서 넣지 않는다.

### 5.4 ServiceAccount

IRSA가 필요한 Workload는 전용 ServiceAccount를 사용한다.

``` text
{service-or-component}-sa
```

예:

``` text
be-sa
ai-sa
jenkins-sa
ebs-csi-sa
```

### 5.5 PersistentVolumeClaim

``` text
{component}-{purpose}-pvc
```

예:

``` text
jenkins-home-pvc
prometheus-data-pvc
grafana-data-pvc
```

StorageClass는 실제 EBS Storage 정책 확정 후 정의한다.

### 5.6 Helm Directory

``` text
helm/
├── frontend/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-develop.yaml
│   ├── values-prod.yaml
│   └── templates/
├── backend/
│   └── ...
├── ai/
│   └── ...
└── infra/
    ├── jenkins/
    ├── argocd/
    ├── ingress/
    ├── cloudflared/
    └── observability/
```

GPU Taint/Toleration, GPU NodeSelector 및 기존 GPU/LLM Scale-to-Zero
전용 설정은 제거한다.

HPA / KEDA / Karpenter는 실제 Scaling 정책이 확정된 경우에만 관련
Resource를 추가한다.

------------------------------------------------------------------------

## 6. ArgoCD / GitOps 구조

FE / BE / AI는 독립 Application Repository를 유지하고, Infrastructure
Team은 단일 Infrastructure Repository를 운영한다.

``` text
infra-repository/
├── terraform/
├── helm/
├── argocd/
├── jenkins/
├── observability/
├── scripts/
├── docs/
└── .github/
```

ArgoCD Directory:

``` text
argocd/
├── develop/
│   ├── frontend.yaml
│   ├── backend.yaml
│   ├── ai.yaml
│   └── observability.yaml
└── prod/
    ├── frontend.yaml
    ├── backend.yaml
    ├── ai.yaml
    └── observability.yaml
```

필요한 경우 Jenkins / Ingress 등 Infrastructure Application을 별도
ArgoCD Application으로 분리한다.

Rollback은 **Git Revert → ArgoCD Auto Sync**를 기본 절차로 한다.

------------------------------------------------------------------------

## 7. CI/CD 및 Container Image Naming

CI/CD 기본 흐름:

``` text
GitHub
  ↓
Jenkins Dynamic Agent
  ↓
Build / Test
  ↓
Docker Image Build
  ↓
Amazon ECR
  ↓
GitOps Repository Image Tag 변경
  ↓
ArgoCD Auto Sync
  ↓
EKS
```

Container Image:

``` text
moongcheap/{service}:{env}-{git-short-sha}
```

`latest` Tag는 사용하지 않는다.

------------------------------------------------------------------------

## 8. 환경 구분

  Environment   용도               Git Branch
  ------------- ------------------ ------------
  `develop`     개발 통합 환경     `develop`
  `prod`        최종 검증 / Demo   `main`

`hotfix/*`는 `main`에서 분기하여 긴급 수정 후 `main`에 Merge하고
`develop`에도 동기화한다.

Terraform / Helm / ArgoCD / Image Tag에서 동일한 Environment
Identifier를 사용한다.

``` text
Terraform → envs/develop
Helm      → values-develop.yaml
ArgoCD    → argocd/develop
Image     → develop-{git-short-sha}
```

### 8.1 현재 배포 제약 (develop 단일 환경 운영)

비용 문제로 인해 `develop`/`prod`를 동시에 운영하기 어려운 상황이므로,
**당분간 AWS EKS Cluster에는 develop 환경만 배포**한다.

-   FE / BE / AI / Infra 모든 서비스는 `develop` Branch 기준 소스
    코드를 AWS 인프라에 반영한다.
-   ArgoCD는 `argocd/develop`만 활성화(Auto Sync)하며,
    `argocd/prod`는 Sync 대상에서 제외한다.
-   `argocd/prod`, `values-prod.yaml`, `terraform/envs/prod`는 삭제하지
    않고 **향후 prod 환경 도입을 위한 비활성 템플릿**으로 유지한다.
-   위 제약으로 5.1절 Namespace(`fe`/`be`/`ai`/`infra`)는 환경 식별자를
    포함하지 않는다. develop 환경만 배포되는 동안에는 고정 Namespace
    기준 Kubernetes Object Name(`fe-deployment`, `be-service`,
    `ai-hpa` 등)이 서로 충돌하지 않는다.
-   추후 prod 환경을 **동일 EKS Cluster에 추가로 배포**하게 되면, 그
    시점에 Namespace(예: `fe-develop` / `fe-prod`) 또는 Kubernetes
    Object Name에 환경 식별자를 추가하도록 5.1~5.3절 Naming 규칙을
    함께 개정하고, ArgoCD Application의 `destination.namespace`도 이에
    맞춰 갱신한다.

------------------------------------------------------------------------

## 9. 변수 관리

### 9.1 Terraform

``` text
terraform/envs/{env}/terraform.tfvars
```

실제 `terraform.tfvars`는 Git에 Commit하지 않고
`terraform.tfvars.example`만 Template으로 관리한다.

### 9.2 Helm

``` text
values-{env}.yaml
```

Helm Values에는 비민감 설정만 저장한다.

### 9.3 Application 환경변수

Backend 기본 후보:

``` text
DB_URL
DB_USERNAME
DB_PASSWORD
AI_API_URL
REDIS_HOST
OPENSEARCH_URL
S3_BUCKET_NAME
AWS_REGION
```

AI 기본 후보:

``` text
DB_URL
DB_USERNAME
DB_PASSWORD
S3_BUCKET_NAME
AWS_REGION
```

실제 FE / BE / AI 환경변수는 각 Application의 최종 접근 대상과 구현에
따라 확정한다.

------------------------------------------------------------------------

## 10. Secret 관리

Secret Store는 **AWS Secrets Manager**를 사용한다.

코드, Container Image, Helm Values 및 Git Repository에 Secret을 평문으로
저장하지 않는다.

Secret Naming:

DB Secret은 3.6절 RDS 규약을 따라 다음 이름 하나로 통일하며, BE·AI Pod는
모두 이 Secret을 조회한다.

``` text
moongcheap-{env}-db-secret
```

DB 외 Secret은 다음 패턴을 따른다.

``` text
moongcheap-{env}-{service}-{purpose}-secret
```

예:

``` text
moongcheap-develop-db-secret
moongcheap-develop-infra-discord-secret
```

Secret 대상 예:

-   DB Username / Password
-   API Token
-   Discord Webhook
-   외부 서비스 Credential

Secrets Manager → Kubernetes Pod 전달 방식은 `[확정 필요]`이다.

### Git Secret 제외 정책

`.gitignore`에는 최소 다음 항목을 포함한다.

``` text
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example

.env
.env.*
*.pem
*.key

kubeconfig
credentials
```

AWS Access Key, Secret Access Key, DB Password, API Token, Webhook
Secret, Private Key 및 실제 Terraform Secret Variable은 Repository에
Commit하지 않는다.

------------------------------------------------------------------------

## 11. Terraform State

Terraform State는 Amazon S3 Remote Backend를 사용한다.

``` text
Bucket = moongcheap-tfstate
Key    = {env}/terraform.tfstate
Region = ap-northeast-2
```

환경별 State:

``` text
develop/terraform.tfstate
prod/terraform.tfstate
```

State Bucket은 일반적인 AWS Infrastructure Open / Close 및
`terraform destroy` 대상에서 제외한다.

State Encryption은 활성화한다.

State Locking은 별도 DynamoDB Table 없이 S3 Backend의
`use_lockfile = true` 옵션(S3 Native Locking)을 사용한다.

------------------------------------------------------------------------

## 12. KT Cloud Naming 및 관리 범위

KT Cloud는 Primary Service Runtime으로 사용하지 않는다.

현재 역할은 다음 두 가지로 제한한다.

1.  AWS Infrastructure Open / Close를 수행하는 Terraform Management
    Environment
2.  AWS Primary Data의 Secondary Backup Storage

KT Cloud Resource에도 가능한 경우 동일 Naming Prefix를 사용한다.

``` text
moongcheap-{env}-{resource}
```

예:

``` text
moongcheap-develop-tf-mgmt
moongcheap-prod-backup
```

KT Cloud Resource Type별 실제 Naming 제약 및 Terraform Provider 지원
여부에 따라 조정할 수 있다.

기존 KT Cloud PostgreSQL Primary DB, pgvector VM 및 Tailscale Subnet
Router 관련 Naming은 폐기한다.

------------------------------------------------------------------------

## 13. 미확정 사항

| 우선순위 | 항목 | 영향 |
| --- | --- | --- |
| 1 | VPC / Subnet CIDR 및 AZ | Terraform Network |
| 2 | Kubernetes Version / EKS Endpoint 정책 | EKS Terraform |
| 3 | FE / BE·AI Node Group Min / Desired / Max | EKS Scaling |
| 4 | FE / BE / AI Port, Probe, Resource, Replica | Helm |
| 5 | HPA / Node Auto Scaling 정책 | Helm / EKS |
| 6 | RDS PostgreSQL Version / DB Name / Username | Terraform / Secret |
| 7 | RDS Backup / Deletion Protection / Final Snapshot | Terraform |
| 8 | S3 Versioning / Encryption / Lifecycle | Terraform |
| 9 | Secrets Manager → Kubernetes Pod 전달 방식 | IAM / Helm |
| 10 | Jenkins / ArgoCD Resource 및 PVC | Helm |
| 11 | Prometheus / Loki / Grafana / Alloy Resource 및 Retention | Helm |
| 12 | KT Cloud Backup 방식 / 주기 / 보존 / Restore 정책 | Backup / DR |
| 13 | Gateway API 전환 여부 및 구현체 | Kubernetes Networking |
