## 1. 개요

AWS를 Primary Cloud로 하여 애플리케이션·데이터 계층을 운영하고, KT Cloud는 AWS 인프라의 Terraform 기반 Open/Close 작업을 수행하는 관리 환경과 백업 이중화용 Storage를 제공하는 Secondary Cloud로 활용한다.

---

## 2. 전체 아키텍처

[image.png](attachment:66554433-9d3f-46b2-8a57-35fdbb68f689\:image.png)

### 구성 요소

| 구성 요소 위치                            |                           |
| ----------------------------------- | ------------------------- |
| Cloudflare Zone / Tunnel            | Cloudflare                |
| NGINX Ingress Controller(협의중)       | EKS Cluster               |
| EKS Control Plane                   | AWS 관리형                   |
| FE Worker Node                      | WEB Private Subnet        |
| BE·AI Worker Node                   | WAS Private Subnet        |
| VPC / Subnet / Route Table / IGW    | AWS                       |
| NAT Instance                        | Public Subnet             |
| ECR / S3 / IAM / Secrets Manager    | AWS                       |
| PostgreSQL + pgvector               | **AWS DB Private Subnet** |
| ElastiCache (Redis)                 | **AWS**                   |
| OpenSearch                          | **AWS**                   |
| Prometheus · Loki · Grafana · Alloy | **BE·AI Worker Node**     |
| Jenkins · ArgoCD                    | **BE·AI Worker Node**     |
| Terraform 관리 환경                     | **KT Cloud**              |
| Backup Storage                      | **KT Cloud**              |

### 워크로드 배치

| Node Group 배치 워크로드                 |                                                                                      |
| ---------------------------------- | ------------------------------------------------------------------------------------ |
| **FE Worker**                      | Frontend (Next.js)                                                                   |
| **BE·AI Worker**                   | Backend (Spring), API Server (FastAPI + Uvicorn), Embedding 등 **CPU 기반 AI Workload** |
| **BE·AI Worker (System Workload)** | Prometheus, Loki, Grafana, Alloy, ArgoCD, Jenkins                                    |
| Pool 외 (클러스터 레벨)                   | NGINX Ingress Controller                                                             |

### 트래픽 흐름

| # 흐름 경로  |                          |                                                                                    |
| -------- | ------------------------ | ---------------------------------------------------------------------------------- |
| 1        | HTTPS Request            | User → Cloudflare DNS → Cloudflare Tunnel → cloudflared → NGINX Ingress Controller |
| 2        | Service Traffic          | NGINX Ingress → CPU Pool (FE / BE / API Server)                                    |
| 3        | AI Request               | Backend · API Server → CPU 기반 AI Workload                                          |
| 4        | DB Query / Response      | Backend · API Server → **AWS RDS PostgreSQL + pgvector**                           |
| 5        | Object Upload / Download | Backend → **AWS S3**                                                               |
| 6        | Outbound                 | Private Subnet → NAT Instance → 외부                                                 |
| 7        | 배포                       | Developer → GitHub → Jenkins → ECR → ArgoCD → EKS                                  |
| 8        | 백업                       | **AWS Primary Data → KT Cloud Backup Storage**                                     |
| 9        | 인프라 관리                   | **KT Cloud Terraform 관리 환경 → AWS API → AWS Infrastructure**                        |

---

## 3. 네트워크

### 3.1 구조

AWS VPC 내부 네트워크는 **Public / WEB Private / WAS Private / DB Private Subnet**으로 분리한다.

Frontend와 Backend·AI Worker Node는 하나의 EKS Cluster에 속하지만, 워크로드 역할에 따라 서로 다른 Private Subnet에 배치한다. 데이터 계층은 AWS 내부 DB Private Subnet에 배치한다.

KT Cloud는 서비스 요청 처리 경로에 포함하지 않으며, **AWS 인프라 Terraform 관리 환경과 백업 이중화용 Storage**를 제공하는 보조 인프라로 사용한다.

| 영역 위치 배치 리소스 용도    |          |                           |                                                               |
| ------------------ | -------- | ------------------------- | ------------------------------------------------------------- |
| Public Subnet      | AWS VPC  | NAT Instance              | Private Subnet의 인터넷 아웃바운드                                     |
| WEB Private Subnet | AWS VPC  | FE Worker Node            | Frontend(Next.js) 워크로드                                        |
| WAS Private Subnet | AWS VPC  | BE·AI Worker Node         | Backend(Spring), API Server, AI CPU Workload, System Workload |
| DB Private Subnet  | AWS VPC  | RDS PostgreSQL + pgvector | 애플리케이션 데이터 및 Vector 데이터                                       |
| Management         | KT Cloud | Terraform 관리 리소스          | AWS 인프라 Terraform Apply / Destroy                             |
| Backup             | KT Cloud | Backup Storage            | AWS Primary Data의 이중화 백업                                      |

#### EKS Subnet 배치

EKS는 **단일 Cluster**로 구성하며, Worker Node Group별로 배치 Subnet을 분리한다.

| Node Group 배치 Subnet 인스턴스 구성 주요 워크로드  |                    |               |                                                                      |
| ------------------------------------- | ------------------ | ------------- | -------------------------------------------------------------------- |
| FE Worker                             | WEB Private Subnet | `t3.small ×2` | Frontend                                                             |
| BE·AI Worker                          | WAS Private Subnet | `t3.large ×N` | Backend, API Server, AI CPU Workload, Jenkins, ArgoCD, Observability |

- FE Worker와 BE·AI Worker는 동일한 EKS Cluster에 포함한다.
- Node Group 생성 시 각 Node Group에 대응하는 Private Subnet ID를 명시한다.
- Pod는 기본적으로 해당 Worker Node가 위치한 Subnet의 네트워크를 사용한다.
- System Workload 전용 Node Group은 초기에는 구성하지 않는다.
- BE·AI Worker의 실제 리소스 사용량과 Jenkins Build 부하를 측정한 뒤 필요 시 전용 Node Group 분리를 검토한다.
- 가용성을 위해 Subnet의 AZ 분산 구성을 적용한다. **AZ 및 CIDR은** **`[확정 필요]`**.

#### Subnet 및 Route Table

| Subnet Public IP 기본 Route 비고  |     |                            |                 |
| ----------------------------- | --- | -------------------------- | --------------- |
| Public                        | 허용  | `0.0.0.0/0 → IGW`          | NAT Instance 배치 |
| WEB Private                   | 비허용 | `0.0.0.0/0 → NAT Instance` | FE Worker 배치    |
| WAS Private                   | 비허용 | `0.0.0.0/0 → NAT Instance` | BE·AI Worker 배치 |
| DB Private                    | 비허용 | 인터넷 기본 Route 없음            | RDS 배치          |

> VPC CIDR, 각 Subnet CIDR 및 AZ 배치는 Terraform 작성 전에 확정한다.

---

### 3.2 외부 진입

외부 사용자의 서비스 요청은 AWS Load Balancer를 사용하지 않고 **Cloudflare Tunnel**을 통해 EKS Cluster 내부로 전달한다.

```
User
  ↓
Cloudflare DNS
  ↓
Cloudflare Tunnel
  ↓
cloudflared
  ↓
NGINX Ingress Controller
  ↓
Kubernetes Service
  ↓
Pod

```

#### Cloudflare 역할

| 구성 역할 적용               |                                         |           |
| ---------------------- | --------------------------------------- | --------- |
| Cloudflare DNS         | 도메인 이름 해석 및 외부 진입점 연결                   | 적용        |
| Cloudflare Tunnel      | AWS 측 Public Inbound 없이 외부 요청 전달        | 적용        |
| cloudflared            | EKS 내부에서 Cloudflare와 Outbound Tunnel 유지 | 적용        |
| Cloudflare Proxy / WAF | Origin 보호, DDoS·WAF                     | `[확정 필요]` |

#### 외부 진입 설정

| 항목 설계                 |                                     |
| --------------------- | ----------------------------------- |
| AWS ALB               | 사용하지 않음                             |
| TLS 종단                | Cloudflare Edge                     |
| Cloudflare ↔ Origin   | Cloudflare Tunnel                   |
| L7 Routing            | NGINX Ingress Controller(현행)        |
| Gateway API           | 전환 검토                               |
| Ingress/Gateway 외부 공개 | Public Load Balancer 방식 사용하지 않음     |
| 도메인 / Host Routing    | `[확정 필요]`                           |
| cloudflared 배치        | EKS Cluster 내부 `[Node Group 확정 필요]` |
| cloudflared Replica   | `[확정 필요]`                           |

#### ingress-nginx EOL 대응

`ingress-nginx` 프로젝트의 서비스 종료에 따라 현행 NGINX Ingress Controller를 유지하면서 Gateway API 기반 구조로의 전환을 검토한다.

| 후보 검토 내용         |                                               |
| ---------------- | --------------------------------------------- |
| NGINX Ingress 유지 | 초기 구축이 단순하지만 EOL 이후 보안 패치 중단 위험 존재            |
| **Gateway API**  | Kubernetes 표준 API. 향후 전환 우선 검토                |
| Istio            | Service Mesh 기능까지 포함되어 현재 프로젝트 규모에서는 운영 부담이 큼 |

Gateway API는 명세이므로 실제 트래픽을 처리하기 위한 Controller 구현체가 별도로 필요하다.

ALB를 사용하지 않는 현재 구조에서는 Envoy Gateway 등의 Cluster 내부 구현체를 검토하며, 구현체 확정 전까지는 NGINX Ingress Controller를 현행 구성으로 사용한다.

---

### 3.3 내부 통신 및 Security Group

WEB / WAS / DB 계층 간 통신은 필요한 방향과 Port만 허용한다.

기본 통신 방향은 다음과 같다.

```
External
   ↓
Cloudflare Tunnel
   ↓
Ingress
   ↓
FE
   ↓
BE / API
   ↓
RDS / Redis / OpenSearch / S3

```

| Source Destination Protocol / Port 용도  |                   |                           |                          |
| -------------------------------------- | ----------------- | ------------------------- | ------------------------ |
| Ingress                                | FE Service        | `[FE Service Port 확정 필요]` | Frontend 요청              |
| Ingress / FE                           | BE Service        | `[BE API Port 확정 필요]`     | Backend API              |
| BE                                     | API / AI Service  | `[AI API Port 확정 필요]`     | AI API 호출                |
| BE / API                               | RDS PostgreSQL    | TCP `5432`                | PostgreSQL / pgvector    |
| BE                                     | ElastiCache Redis | TCP `6379`                 | Cache                    |
| BE                                     | OpenSearch        | TCP `443`                  | Search                   |
| Workload                               | S3                | HTTPS `443`               | Object Upload / Download |

- Security Group은 `0.0.0.0/0` 기반 내부 허용을 지양하고 **Source Security Group 기반 접근 제어**를 우선한다.
- RDS는 Public Access를 비활성화한다.
- DB Security Group의 PostgreSQL `5432` Inbound는 애플리케이션 접근이 필요한 Security Group에서만 허용한다.
- 실제 FE / BE / AI Service Port는 각 파트의 API 및 Container Port 확정 후 반영한다.
- Redis와 OpenSearch는 확정 구성으로, Security Group 및 Terraform에 필수 구성 요소로 반영한다.

---

### 3.4 아웃바운드

Private Subnet에서 인터넷으로 나가는 일반 아웃바운드 트래픽은 **NAT Gateway가 아닌 NAT Instance**를 경유한다.

```
WEB / WAS Private Subnet
        ↓
Private Route Table
        ↓
NAT Instance
        ↓
Internet Gateway
        ↓
Internet

```

#### NAT Instance 사양

| 항목 값                     |                          |
| ------------------------ | ------------------------ |
| Instance Type            | `t3a.micro`              |
| 배치                       | Public Subnet            |
| Public IPv4              | Elastic IP 연결            |
| Source/Destination Check | 비활성화                     |
| 역할                       | Private Subnet 인터넷 아웃바운드 |
| Tailscale Router         | 사용하지 않음                  |
| 관리                       | Terraform                |
| 장애 대응                    | 재생성 절차 기반                |

- WEB/WAS Private Route Table의 인터넷 목적지(`0.0.0.0/0`)는 NAT Instance를 대상으로 설정한다.
- NAT Instance는 SPOF이므로 장애 발생 시 모니터링 알림 후 Terraform 기반 재생성 절차로 복구한다.
- NAT Instance 장애는 WEB/WAS Private Subnet의 외부 아웃바운드에 영향을 준다.
- VPC Endpoint는 초기부터 무조건 구성하지 않고 실제 NAT 트래픽을 측정한 뒤 비용 절감 효과가 있는 서비스에 적용한다.
- DB Private Subnet은 일반 인터넷 아웃바운드가 필요하지 않은 구조를 기본으로 한다.

---

### 3.5 KT Cloud 관리 환경 연계

KT Cloud는 AWS 서비스 Runtime과 직접 연결되는 데이터 계층으로 사용하지 않는다.

KT Cloud에는 AWS 인프라의 Open/Close 작업을 수행하기 위한 **Terraform 관리 환경**을 구성한다.

```
KT Cloud
Terraform Management Resource
        ↓ HTTPS / AWS API
AWS IAM Authentication
        ↓
Terraform
        ↓
AWS Infrastructure

```

Terraform 관리 환경에서 수행하는 주요 작업은 다음과 같다.

- `terraform init`
- `terraform plan`
- `terraform apply`
- `terraform destroy`
- 오전 AWS 인프라 Open
- 오후 AWS 인프라 Close

KT Cloud 관리 환경에서 AWS API 접근에 필요한 인증정보는 코드 또는 Terraform 변수 파일에 평문으로 저장하지 않는다.

구체적인 IAM 인증 방식 및 Terraform State 접근 방식은 `[확정 필요]`이다.

---

### 3.6 KT Cloud 백업 이중화

AWS를 Primary 데이터 저장소로 사용하고, KT Cloud Storage를 **Secondary Backup Storage**로 사용한다.

```
AWS Primary Data
   ├─ RDS PostgreSQL + pgvector
   └─ S3 Object Storage
             ↓
       Backup Process
             ↓
KT Cloud Backup Storage

```

| 데이터 Primary Secondary Backup  |         |                  |
| ----------------------------- | ------- | ---------------- |
| PostgreSQL / pgvector         | AWS RDS | KT Cloud Storage |
| Object Storage                | AWS S3  | KT Cloud Storage |

- KT Cloud Storage는 서비스 Runtime에서 직접 조회하는 Primary Storage로 사용하지 않는다.
- 서비스 요청 처리 중 KT Cloud와의 네트워크 RTT에 의존하지 않는다.
- 백업 방식, 주기, 보존 기간, 암호화 및 복구 절차는 `[확정 필요]`이다.
- 백업 경로 구현 방식이 확정되기 전까지 Site-to-Site VPN 또는 Tailscale 연결을 전제로 하지 않는다.

---

## 4. EKS 클러스터

### 4.1 클러스터

서비스 워크로드는 AWS `ap-northeast-2` 리전의 **단일 EKS Cluster**에서 운영한다.

Frontend와 Backend·AI는 동일한 Cluster를 사용하되, Node Group과 Subnet을 분리하여 워크로드를 배치한다.

| 항목 값                  |                    |
| --------------------- | ------------------ |
| 클러스터 수                | 1                  |
| 리전                    | `ap-northeast-2`   |
| 가용 영역(AZ)             | `[확정 필요]`          |
| Kubernetes Version    | `[확정 필요]`          |
| Cluster Endpoint 접근   | `[확정 필요]`          |
| Worker Node Public IP | 사용하지 않음            |
| FE Worker 배치          | WEB Private Subnet |
| BE·AI Worker 배치       | WAS Private Subnet |

#### EKS Add-on

| Add-on 용도 적용   |                                |    |
| -------------- | ------------------------------ | -- |
| VPC CNI        | Pod 네트워크 및 VPC IP 할당           | 필수 |
| CoreDNS        | Cluster 내부 DNS                 | 필수 |
| kube-proxy     | Kubernetes Service 네트워크        | 필수 |
| EBS CSI Driver | EBS 기반 PersistentVolume 제공     | 필수 |
| Metrics Server | HPA 및 Pod/Node Resource Metric | 필수 |

- GPU Node를 사용하지 않으므로 **NVIDIA Device Plugin은 설치하지 않는다.**
- EBS CSI Driver가 AWS 리소스에 접근할 수 있도록 필요한 IAM 권한을 구성한다.
- EKS Add-on Version은 사용하는 Kubernetes Version과의 호환성을 기준으로 결정한다.

---

### 4.2 Node Group

EKS Worker Node는 **FE Worker Node Group과 BE·AI Worker Node Group**으로 분리한다.

초기에는 Observability 및 CI/CD 전용 Node Group을 별도로 구성하지 않고 BE·AI Worker에 함께 배치한다.

| Node Group 배치 Subnet Instance Type 배치 워크로드  |                    |            |                                                                                                 |
| ------------------------------------------- | ------------------ | ---------- | ----------------------------------------------------------------------------------------------- |
| **FE Worker**                               | WEB Private Subnet | `t3.small` | Frontend (Next.js)                                                                              |
| **BE·AI Worker**                            | WAS Private Subnet | `t3.large` | Backend(Spring), API Server, AI CPU Workload, Jenkins, ArgoCD, Prometheus, Loki, Alloy, Grafana |

#### FE Worker Node Group

| 항목 값          |                    |
| ------------- | ------------------ |
| Instance Type | `t3.small`         |
| vCPU / Memory | `2 vCPU / 2 GiB`   |
| Capacity Type | On-Demand          |
| Desired Size  | `2`                |
| Min Size      | `[확정 필요]`          |
| Max Size      | `[확정 필요]`          |
| Subnet        | WEB Private Subnet |
| Public IP     | 사용하지 않음            |
| Root Volume   | 20 GiB EBS         |

#### BE·AI Worker Node Group

| 항목 값          |                        |
| ------------- | ---------------------- |
| Instance Type | `t3.large`             |
| vCPU / Memory | `2 vCPU / 8 GiB`       |
| Capacity Type | On-Demand              |
| Desired Size  | `[확정 필요]`              |
| Min Size      | `[확정 필요]`              |
| Max Size      | `4` *(현재 비용 산정 기준 상한)* |
| Subnet        | WAS Private Subnet     |
| Public IP     | 사용하지 않음                |
| Root Volume   | **20 GiB EBS**         |

> `t3.large ×4`는 상시 실행되는 고정 Node 수가 아니라 **현재 비용 산정에서 사용한 최대 구성 기준**이다. 실제 Desired/Min 값은 각 파트의 Pod Request와 부하 테스트 결과를 기준으로 확정한다.

#### 워크로드 배치 제어

Node Group별 워크로드 배치를 명확하게 하기 위해 Kubernetes Label을 사용한다.

예시:

```yaml
FE Worker:
  workload: frontend

BE·AI Worker:
  workload: backend-ai

```

워크로드는 `nodeSelector` 또는 `nodeAffinity`를 이용해 대상 Node Group에 배치한다.

- Frontend → FE Worker
- Backend / API / AI → BE·AI Worker
- Jenkins / ArgoCD / Observability → BE·AI Worker
- 모든 애플리케이션 Pod에 `resources.requests` / `resources.limits`를 지정한다.
- Pod Resource 값은 각 파트의 최종 요구 사양을 반영한다.
- 초기 구조에서는 GPU Taint/Toleration 설정을 사용하지 않는다.
- System Workload 전용 Node Group이 필요해질 경우 별도의 Label/Taint 정책을 추가한다.

---

### 4.3 설치 컴포넌트

| 구분 컴포넌트 초기 배치  |                          |                            |
| -------------- | ------------------------ | -------------------------- |
| 외부 진입          | NGINX Ingress Controller | EKS Cluster                |
| Tunnel         | cloudflared              | `[Node Group 확정 필요]`       |
| 관찰성            | Prometheus               | BE·AI Worker               |
| 관찰성            | Loki                     | BE·AI Worker               |
| 관찰성            | Alloy                    | BE·AI Worker               |
| 관찰성            | Grafana                  | BE·AI Worker               |
| CI             | Jenkins Controller       | BE·AI Worker               |
| CI             | Jenkins Dynamic Agent    | BE·AI Worker               |
| CD             | ArgoCD                   | BE·AI Worker               |
| 시스템            | Metrics Server           | EKS Cluster                |
| 시스템            | EBS CSI Driver           | EKS Add-on                 |
| 확장             | HPA                      | 애플리케이션 Pod `[적용 대상 확정 필요]` |
| 확장             | Karpenter                | `[도입 여부 확정 필요]`            |
| 확장             | KEDA                     | `[도입 여부 확정 필요]`            |

#### Pod Auto Scaling

애플리케이션 Pod는 처음부터 높은 CPU/Memory를 할당하기보다 작은 Resource Request로 시작하고, 부하 테스트 결과를 기반으로 적정 Resource 및 Replica 수를 결정한다.

HPA 적용 시 다음 항목을 워크로드별로 명시한다.

| 항목 값                   |           |
| ---------------------- | --------- |
| 적용 Workload            | `[확정 필요]` |
| Minimum Replica        | `[확정 필요]` |
| Maximum Replica        | `[확정 필요]` |
| CPU Target Utilization | `[확정 필요]` |
| Memory 기반 Scaling      | `[확정 필요]` |

Karpenter 또는 Node Group Auto Scaling을 통한 **Node Scaling 정책은 Pod Resource 및 HPA 정책 확정 후 결정한다.**

---

### 4.4 HA 정책

애플리케이션 계층은 **복수 Worker Node + 복수 Pod Replica + Kubernetes Probe + Rolling Update**를 기본 가용성 전략으로 사용한다.

| 항목 정책                    |                             |
| ------------------------ | --------------------------- |
| FE Replica               | `[부하 테스트 후 확정]`             |
| BE Replica               | `[부하 테스트 후 확정]`             |
| API / AI Replica         | `[부하 테스트 후 확정]`             |
| Readiness Probe          | 적용                          |
| Liveness Probe           | 적용                          |
| Startup Probe            | 초기화 시간이 긴 Workload에 필요 시 적용 |
| Rolling Update           | 기본 적용                       |
| PodDisruptionBudget(PDB) | `[적용 대상 확정 필요]`             |
| Multi-AZ Worker 배치       | 적용                          |
| FE Worker Node           | 최소 2개 Node 구성               |
| BE·AI Worker Node        | 복수 Node 기반 구성               |

#### Probe

각 애플리케이션 파트는 Helm Chart 작성을 위해 다음 정보를 인프라 파트에 제공해야 한다.

| 항목 FE BE AI            |           |           |           |
| ---------------------- | --------- | --------- | --------- |
| Container Port         | `[확정 필요]` | `[확정 필요]` | `[확정 필요]` |
| Readiness Path         | `[확정 필요]` | `[확정 필요]` | `[확정 필요]` |
| Liveness Path          | `[확정 필요]` | `[확정 필요]` | `[확정 필요]` |
| Startup Probe 필요 여부    | `[확정 필요]` | `[확정 필요]` | `[확정 필요]` |
| CPU Request / Limit    | `[확정 필요]` | `[확정 필요]` | `[확정 필요]` |
| Memory Request / Limit | `[확정 필요]` | `[확정 필요]` | `[확정 필요]` |
| 초기 Replica             | `[확정 필요]` | `[확정 필요]` | `[확정 필요]` |

Readiness Probe는 초기화가 완료되지 않은 Pod로 트래픽이 전달되는 것을 방지하고, Liveness Probe는 비정상 상태의 Pod를 자동 재시작하기 위해 사용한다.

Startup Probe는 기존 vLLM 전용 정책으로 사용하지 않고, **실제로 초기 구동 시간이 긴 애플리케이션에 한해 적용한다.**

---

### 4.5 미확정 IaC 입력값

Terraform 및 Helm 코드 작성 전에 다음 값을 최종 확정해야 한다.

| 구분 미확정 값         |                                                 |
| ---------------- | ----------------------------------------------- |
| EKS              | Kubernetes Version                              |
| EKS              | Cluster Endpoint Public / Private Access 정책     |
| Network          | EKS가 사용할 AZ                                     |
| FE Node Group    | Min / Max Size                                  |
| BE·AI Node Group | Min / Desired Size                              |
| Node             | Root EBS Volume 타입 *(크기: 20 GiB 확정)*             |
| cloudflared      | Node Group / Replica                            |
| Scaling          | HPA 적용 대상 및 Threshold                           |
| Scaling          | Karpenter 또는 Node Auto Scaling 방식               |
| FE               | Port / Probe / Resource / Replica               |
| BE               | Port / Probe / Resource / Replica               |
| AI               | Port / Probe / Resource / Replica               |
| PDB              | 적용 Workload 및 `minAvailable` / `maxUnavailable` |

---

## 5. AI 워크로드

AI 워크로드는 **GPU Node를 사용하지 않고 CPU 기반 Pod로 구성**하며, EKS의 BE·AI Worker Node Group에 배치한다.

### 5.1 구성

| 구성 모델 / 프레임워크 배치  |                   |              |
| ----------------- | ----------------- | ------------ |
| AI API Server     | FastAPI + Uvicorn | BE·AI Worker |
| Embedding         | `[AI 파트 확정 필요]`   | BE·AI Worker |
| 기타 AI Workload    | `[AI 파트 확정 필요]`   | BE·AI Worker |

- 별도의 GPU Node Group은 구성하지 않는다.
- AI Pod는 WAS Private Subnet에 위치한 **BE·AI Worker Node Group**에 배치한다.
- AI Workload의 CPU / Memory Request 및 Limit은 AI 파트의 실제 요구 사양을 기준으로 결정한다.
- AI Pod의 Replica 및 HPA 정책은 초기 부하 테스트 결과를 기준으로 확정한다.

### 5.2 Pod 배치 및 Resource

Helm Chart에서 AI Workload를 명확하게 배치할 수 있도록 BE·AI Worker Node Group의 Label을 사용한다.

```yaml
nodeSelector:
  workload: backend-ai

```

AI 파트에서 다음 정보를 확정한 뒤 Helm `Deployment`, `Service`, `HPA`에 반영한다.

| 항목 값                 |              |
| -------------------- | ------------ |
| Container Image      | `[확정 필요]`    |
| Container Port       | `[확정 필요]`    |
| CPU Request          | `[확정 필요]`    |
| CPU Limit            | `[확정 필요]`    |
| Memory Request       | `[확정 필요]`    |
| Memory Limit         | `[확정 필요]`    |
| Initial Replica      | `[확정 필요]`    |
| Minimum Replica      | `[확정 필요]`    |
| Maximum Replica      | `[확정 필요]`    |
| HPA CPU Threshold    | `[확정 필요]`    |
| Readiness Probe Path | `[확정 필요]`    |
| Liveness Probe Path  | `[확정 필요]`    |
| Startup Probe        | `[필요 여부 확인]` |

### 5.3 통신

AI Workload는 외부에 직접 노출하지 않고 Kubernetes 내부 Service를 통해 Backend 또는 API Server와 통신한다.

```
Backend
   ↓
AI API Service
   ↓
AI Pod
   ├─ RDS PostgreSQL + pgvector
   └─ S3

```

| Source Destination Port 용도  |                |                             |                 |
| --------------------------- | -------------- | --------------------------- | --------------- |
| Backend                     | AI API Service | `[AI API Port 확정 필요]`       | AI 기능 호출        |
| AI Workload                 | RDS PostgreSQL | TCP `5432` `[접근 필요 시]`      | 데이터 / Vector 조회 |
| AI Workload                 | S3             | HTTPS `443` `[접근 필요 시]`     | Object 조회       |
| Prometheus                  | AI Workload    | `[Metrics Port/Path 확정 필요]` | Metrics 수집      |

- AI Service는 기본적으로 `ClusterIP`로 구성한다.
- 외부에서 AI Pod로 직접 접근하는 경로는 구성하지 않는다.
- RDS 및 S3 접근 여부는 AI 애플리케이션 구조 확정 후 반영한다.
- AWS 리소스 접근이 필요한 경우 Access Key를 Pod에 직접 저장하지 않고 IAM 기반 권한 부여 방식을 사용한다.

### 5.4 Observability

AI Workload 역시 다른 애플리케이션 Pod와 동일한 Observability 체계를 적용한다.

- **Metrics** → Prometheus
- **Logs** → Alloy → Loki
- **Visualization / Alert** → Grafana
- AI 애플리케이션 자체 Metrics Endpoint가 제공되는 경우 Prometheus 수집 대상으로 추가한다.
- Metrics Port 및 Path는 AI 파트 구현 확정 후 Helm 설정에 반영한다.

---

## 6. 데이터 계층

서비스의 Primary Data Layer는 AWS에 구성한다.

관계형 데이터와 Vector 데이터는 **Amazon RDS for PostgreSQL + pgvector**, Object 데이터는 **Amazon S3**에 저장한다. KT Cloud Storage는 서비스 Runtime에서 직접 사용하는 데이터 계층이 아니라 **Secondary Backup Storage**로 사용한다.

### 6.1 데이터 계층 구성

| 구성 배치 용도 접근 경로   |                             |                     |                    |
| ---------------- | --------------------------- | ------------------- | ------------------ |
| PostgreSQL       | AWS RDS / DB Private Subnet | 애플리케이션 데이터          | BE·AI → TCP `5432` |
| pgvector         | RDS PostgreSQL Extension    | Vector 데이터          | PostgreSQL과 동일     |
| Object Storage   | AWS S3                      | 이미지·파일 등 Object 데이터 | HTTPS `443`        |
| Redis            | Amazon ElastiCache          | Cache               | TCP `6379`         |
| OpenSearch       | Amazon OpenSearch Service   | 서비스 검색              | HTTPS `443`        |
| Secondary Backup | KT Cloud Storage            | 데이터 이중화 백업          | `[백업 방식 확정 필요]`    |

---

### 6.2 RDS PostgreSQL + pgvector

PostgreSQL은 **Amazon RDS for PostgreSQL**을 사용하고, Vector 데이터는 별도의 Vector DB를 구성하지 않고 PostgreSQL의 `pgvector` Extension을 사용한다.

| 항목 값                |                               |
| ------------------- | ----------------------------- |
| Service             | Amazon RDS for PostgreSQL     |
| Engine              | PostgreSQL                    |
| Region              | `ap-northeast-2`              |
| 배치                  | DB Private Subnet             |
| DB Subnet Group     | 복수 AZ의 DB Private Subnet으로 구성 |
| Multi-AZ            | 적용                            |
| Storage             | `50 GiB`                      |
| Storage Type        | General Purpose SSD (`gp3`)   |
| Instance Class      | **`db.t4g.medium`**           |
| Port                | TCP `5432`                    |
| Public Access       | 비활성화                          |
| pgvector            | PostgreSQL Extension으로 구성     |
| Database Name       | `[확정 필요]`                     |
| Master Username     | `[확정 필요]`                     |
| Password 관리         | AWS Secrets Manager           |
| Backup Retention    | `[확정 필요]`                     |
| Deletion Protection | `[확정 필요]`                     |
| Final Snapshot      | `[정책 확정 필요]`                  |

#### 접근 제어

RDS는 인터넷에 직접 공개하지 않는다.

```
BE / AI Workload
       ↓
RDS Security Group
       ↓ TCP 5432
RDS PostgreSQL
       ↓
pgvector Extension

```

- `Publicly Accessible = false`
- RDS Security Group의 TCP `5432` Inbound는 DB 접근이 필요한 애플리케이션 Security Group에서만 허용한다.
- DB Credential은 Helm `values.yaml`, Kubernetes Manifest 또는 Terraform 코드에 평문으로 저장하지 않는다.
- DB Credential은 AWS Secrets Manager에서 관리한다.
- 애플리케이션의 Secret 주입 방식은 `[확정 필요]`이다.

---

### 6.3 S3 Object Storage

이미지 및 파일 등의 Object 데이터는 **Amazon S3를 Primary Object Storage**로 사용한다.

| 항목 값             |                             |
| ---------------- | --------------------------- |
| Service          | Amazon S3                   |
| Region           | `ap-northeast-2`            |
| Bucket Name      | `moongcheap-{env}-object`       |
| Public Access    | 차단                          |
| Versioning       | `[확정 필요]`                   |
| Encryption       | `[확정 필요]`                   |
| Lifecycle Policy | `[확정 필요]`                   |
| 접근 주체            | `[BE / AI 등 실제 요구사항 확정 필요]` |
| 접근 방식            | IAM 기반 권한 부여                |
| Protocol         | HTTPS `443`                 |

S3 Bucket은 Public Access를 허용하지 않으며, EKS Workload에서 S3 접근이 필요한 경우 Access Key를 Pod에 직접 저장하지 않고 **IAM 기반 권한 부여 방식**을 사용한다.

---

### 6.4 Redis / OpenSearch

Redis와 OpenSearch는 `naming_convention_V2.md` 3.8·3.9절 기준 **확정 구성 요소**이다.

| 서비스 | AWS 서비스 | 용도 | 스펙 |
| --- | --- | --- | --- |
| Redis | Amazon ElastiCache | Cache / Session 등 | Redis OSS / `cache.t4g.small ×2` / On-Demand |
| OpenSearch | Amazon OpenSearch Service | 서비스 검색 | `t3.small.search ×1`, gp3 10 GiB, 3000 IOPS, On-Demand |

OpenSearch는 **로그 수집 및 모니터링 용도로 사용하지 않는다.**

로그는 다음 Observability Stack으로 처리한다.

```
Application Log
      ↓
Grafana Alloy
      ↓
Loki
      ↓
Grafana

```

따라서 OpenSearch는 서비스 검색 등 **애플리케이션 기능을 위한 Search Engine 역할로 한정**한다.

---

### 6.5 KT Cloud Secondary Backup

KT Cloud Storage는 AWS Primary Data Layer의 장애 또는 데이터 손실에 대비한 **Secondary Backup Storage**로 사용한다.

```
AWS Primary Data
├─ RDS PostgreSQL + pgvector
└─ S3 Object Storage
          ↓
    Backup Process
          ↓
KT Cloud Backup Storage

```

| 백업 대상 Primary Secondary  |         |                  |
| ------------------------ | ------- | ---------------- |
| PostgreSQL / pgvector    | AWS RDS | KT Cloud Storage |
| Object 데이터               | AWS S3  | KT Cloud Storage |

- KT Cloud Storage는 서비스 Runtime에서 직접 조회하지 않는다.
- AWS ↔ KT Cloud 간 실시간 DB Query는 발생하지 않는다.
- 기존 Tailscale Site-to-Site 기반 DB 접근 구조는 사용하지 않는다.
- PostgreSQL Backup 방식은 `[확정 필요]`이다.
- S3 → KT Cloud Storage Backup 방식은 `[확정 필요]`이다.
- 백업 주기는 `[확정 필요]`이다.
- 백업 보존 기간은 `[확정 필요]`이다.
- 백업 암호화 정책은 `[확정 필요]`이다.
- Restore 절차 및 RTO/RPO는 `[확정 필요]`이다.

---

### 6.6 데이터 보호 정책

Terraform을 이용한 AWS 인프라 Open/Close 작업 시 데이터 계층은 일반 Compute Resource와 분리하여 보호한다.

| 리소스 일반 Close 시 처리       |           |
| ----------------------- | --------- |
| EKS Worker / Compute    | 종료·축소 대상  |
| NAT Instance            | 종료·재생성 가능 |
| RDS PostgreSQL          | 데이터 보호 대상 |
| S3                      | 유지        |
| EBS/PVC 중요 데이터          | 보호        |
| KT Cloud Backup Storage | 유지        |

RDS, S3 및 중요 Persistent Data는 일반적인 Terraform Destroy 과정에서 데이터가 삭제되지 않도록 보호 정책을 적용한다.

구체적인 Terraform Lifecycle 정책과 RDS 종료/유지 방식은 비용 관리 Runbook의 Open/Close 절차와 동일하게 유지한다.

---

### 6.7 미확정 IaC 입력값

Terraform 및 애플리케이션 Helm Chart 작성 전에 다음 값을 확정한다.

| 구분 미확정 값  |                                         |
| --------- | --------------------------------------- |
| RDS       | PostgreSQL Engine Version               |
| RDS       | Database Name                           |
| RDS       | Backup Retention Period                 |
| RDS       | Deletion Protection / Final Snapshot 정책 |
| S3        | Versioning                              |
| S3        | Encryption                              |
| S3        | Lifecycle Policy                        |
| IAM       | EKS Workload의 RDS/S3 접근 방식              |
| KT Cloud  | Backup Storage Spec                     |
| Backup    | RDS → KT Cloud Backup 방식                |
| Backup    | S3 → KT Cloud Backup 방식                 |
| Backup    | 주기 / 보존 기간 / 암호화                        |
| DR        | Restore 절차 / RTO / RPO                  |

---

## 7. 클러스터 운영 구성

### 7.1 IAM

EKS Pod에서 AWS Resource에 접근할 때 컨테이너 내부에 장기 Access Key / Secret Access Key를 저장하지 않고 **IAM Role 기반 권한 부여 방식**을 사용한다.

| 접근 주체 AWS Resource 필요 권한  |                 |                                  |
| ------------------------- | --------------- | -------------------------------- |
| EBS CSI Driver            | EBS / EC2 API   | EBS Volume 생성·연결·삭제              |
| Jenkins Agent             | ECR             | Image Push / Pull                |
| 애플리케이션 Pod                | S3              | Object Read / Write `[대상 확정 필요]` |
| Secret 조회 컴포넌트            | Secrets Manager | Secret Read                      |
| 기타 Workload               | AWS Resource    | 최소 권한 원칙에 따라 개별 정의               |

- Pod → AWS IAM 연동 방식은 **IRSA**를 프로젝트 표준으로 사용한다.
- IAM Role은 Workload별로 분리하고 최소 권한 원칙을 적용한다.
- AWS Access Key / Secret Access Key를 Container Image, Helm `values.yaml`, Kubernetes Manifest 또는 Git Repository에 평문으로 저장하지 않는다.
- Secret Store는 **AWS Secrets Manager**를 사용한다.
- Kubernetes Pod에 Secret을 전달하는 구체적인 방식은 `[확정 필요]`이다.
- Secret Naming 및 관리 규칙은 네이밍/Secret 관리 문서를 따른다.

---

### 7.2 CI/CD 배치

CI/CD Pipeline 규칙은 Git 협업 문서를 기준으로 하며, 클라우드 인프라에서는 Jenkins와 ArgoCD의 실행 환경 및 Persistent Resource를 제공한다.

초기에는 별도의 CI/CD 전용 Node Group을 구성하지 않고 **BE·AI Worker Node Group**에 배치한다.

| 구성 배치 운영 방식             |                        |                                  |
| ----------------------- | ---------------------- | -------------------------------- |
| Jenkins Controller      | BE·AI Worker           | PVC 사용, Configuration as Code 적용 |
| Jenkins Agent           | Kubernetes Dynamic Pod | Build 시 생성, 완료 후 삭제              |
| ArgoCD                  | BE·AI Worker           | GitOps 기반 배포                     |
| Container Image         | Amazon ECR             | 서비스별 Repository 사용               |
| Jenkins Persistent Data | EBS 기반 PVC             | 동일 AZ 내 Controller 재배치 시 데이터 유지 (AZ 상이 시 7.2절 복구 절차 참고) |

#### CI/CD 흐름

```
Developer
    ↓
GitHub
    ↓
Jenkins Controller
    ↓
Dynamic Jenkins Agent
    ↓
Build / Test
    ↓
Docker Image Build
    ↓
Amazon ECR
    ↓
GitOps Manifest / Helm values 변경
    ↓
ArgoCD
    ↓
EKS

```

- Jenkins Controller는 Stateful Workload이므로 EBS CSI Driver를 이용한 PVC를 사용한다.
- Jenkins 설정은 Configuration as Code 방식으로 관리하여 Controller 재생성 시 복구할 수 있도록 한다.
- Jenkins Agent는 Kubernetes Dynamic Pod 방식으로 생성하며 Build 완료 후 삭제한다.
- Jenkins Agent가 ECR에 Image를 Push할 수 있도록 필요한 IAM 권한을 부여한다.
- ArgoCD Rollback은 Git의 이전 정상 상태로 되돌리는 **Git Revert 기반 절차**를 기본으로 한다.
- Container Image Tag 및 Repository Naming은 Git 협업 문서를 따른다.
- `latest` Tag는 사용하지 않는다.
- Jenkins Build로 인해 BE·AI Worker의 리소스가 부족해지는 경우 CI/CD 전용 Node Group 분리를 검토한다.

#### Jenkins PVC AZ 제약 및 복구 절차

EBS 볼륨은 생성된 **Availability Zone에서만 노드에 연결**할 수 있다. Jenkins Controller Pod가 볼륨이 있는 AZ가 아닌 다른 AZ의 노드로 재배치되면 PVC Mount가 실패하여 Pod가 기동하지 못한다. **EBS CSI Driver를 사용한다는 사실만으로 교차 AZ 재배치·복구가 보장되지 않는다.**

이를 방지하기 위해 다음을 적용한다.

- Jenkins Controller가 사용하는 EBS CSI `StorageClass`는 `volumeBindingMode: WaitForFirstConsumer`로 설정한다. 이를 통해 PV가 미리 특정 AZ에 생성되지 않고, Pod가 스케줄링된 이후 그 노드의 AZ에 맞춰 볼륨이 생성된다.
- Jenkins Controller Pod는 최초 스케줄된 AZ에 고정되도록 하며, 이후 재배치는 `nodeAffinity` / `topology.kubernetes.io/zone` Label을 통해 동일 AZ의 노드로만 제한한다.
- BE·AI Worker Node Group은 최소 2개 이상의 AZ에 걸쳐 구성되므로, 다른 AZ 노드로의 임의 재배치를 막기 위한 Affinity 설정 없이는 위 장애가 발생할 수 있다는 점에 유의한다.

해당 AZ 자체에 장애가 발생해 동일 AZ 내 재배치가 불가능한 경우(교차 AZ 복구)에는 자동 복구를 보장하지 않으며 다음 절차를 따른다.

1.  기존 EBS 볼륨의 최신 Snapshot을 확인한다(Snapshot 정책은 6.6절 데이터 보호 정책을 따른다).
2.  장애 AZ가 아닌 다른 AZ에 Snapshot으로부터 신규 EBS 볼륨을 생성한다.
3.  Jenkins Controller PVC/PV를 신규 볼륨을 가리키도록 재생성하고 Controller Pod를 해당 AZ 노드로 재스케줄한다.
4.  Configuration as Code로 관리되는 설정은 Controller 재생성 시 함께 복구되는지 확인한다.
5.  Snapshot 시점 이후의 Job 이력·설정 변경 유실 가능성을 팀에 공유한다.

Snapshot 주기, RPO/RTO 목표 및 자동화 여부는 `[확정 필요]`이다.

#### CI/CD Resource Spec

| 항목 값                                      |                      |
| ----------------------------------------- | -------------------- |
| Jenkins Controller CPU Request / Limit    | `[확정 필요]`            |
| Jenkins Controller Memory Request / Limit | `[확정 필요]`            |
| Jenkins Controller PVC Size               | `[확정 필요]`            |
| Jenkins Agent CPU / Memory                | `[Build 부하 측정 후 확정]` |
| Jenkins Agent 동시 실행 수                     | `[확정 필요]`            |
| ArgoCD CPU / Memory                       | `[확정 필요]`            |
| ArgoCD Replica                            | `[확정 필요]`            |

---

### 7.3 Observability

클러스터 및 애플리케이션의 Metrics와 Logs는 **Prometheus / Alloy / Loki / Grafana** Stack으로 통합 관리한다.

초기에는 별도의 Observability Node Group을 구성하지 않고 **BE·AI Worker Node Group**에 배치한다.

| 계층 구성 역할            |                  |                                           |
| ------------------- | ---------------- | ----------------------------------------- |
| Metrics             | Prometheus       | Node / Kubernetes / Application Metric 수집 |
| Logs                | Grafana Alloy    | Container Log 수집 및 Loki 전달                |
| Log Storage / Query | Loki             | Log 저장 및 조회                               |
| Dashboard           | Grafana          | Metric / Log 시각화                          |
| Alert               | Grafana Alerting | Discord Webhook 알림                        |

#### Metrics 흐름

```
Node / Kubernetes / Application
              ↓
          Prometheus
              ↓
           Grafana
              ↓
      Grafana Alerting
              ↓
           Discord

```

#### Log 흐름

```
Container Log
      ↓
Grafana Alloy
      ↓
     Loki
      ↓
   Grafana

```

#### 수집 대상

- EKS Node CPU / Memory / Disk / Network
- Kubernetes Node / Pod / Deployment 상태
- Pod CPU / Memory 사용량
- Pod Restart / Crash 상태
- FE / BE / AI Application Metrics `[제공 시]`
- Container stdout / stderr Log
- Jenkins / ArgoCD 운영 지표 `[필요 항목 확정 필요]`

기존 GPU 및 vLLM 기반 워크로드를 사용하지 않으므로 **GPU Metric 및** **`vLLM /metrics`****는 수집 대상에서 제외한다.**

Application Metric Endpoint(`/metrics`)의 제공 여부, Port 및 Path는 FE / BE / AI 각 파트에서 확인하여 Prometheus 설정에 반영한다.

---

### 7.4 Observability Resource 및 보존 정책

Prometheus와 Loki는 데이터 보존이 필요한 Stateful Component이므로 저장 방식과 보존 기간을 명시한다.

| 항목 값                       |                                   |
| -------------------------- | --------------------------------- |
| Prometheus CPU / Memory    | `[확정 필요]`                         |
| Prometheus Storage         | `[확정 필요]`                         |
| Prometheus Retention       | `[확정 필요]`                         |
| Loki CPU / Memory          | `[확정 필요]`                         |
| Loki Storage Backend       | `[확정 필요]`                         |
| Loki Retention             | `[확정 필요]`                         |
| Grafana CPU / Memory       | `[확정 필요]`                         |
| Grafana Persistent Storage | `[필요 여부 확정]`                      |
| Alloy CPU / Memory         | `[확정 필요]`                         |
| Discord Webhook            | Secrets Manager 등 Secret 관리 정책 적용 |

> OpenSearch는 Log Monitoring 용도로 중복 사용하지 않는다. OpenSearch는 애플리케이션의 서비스 검색 기능을 담당하고, 운영 Log는 Alloy → Loki → Grafana 체계로 관리한다.

---

### 7.5 모니터링 및 Alert 정책

Grafana Dashboard와 Alert Rule은 실제 운영 시 필요한 장애 징후를 중심으로 구성한다.

초기 Alert 후보는 다음과 같다.

| 대상 Alert 조건  |                                                       |
| ------------ | ----------------------------------------------------- |
| Node         | CPU / Memory 사용률 임계값 초과 `[Threshold 확정 필요]`           |
| Pod          | 반복 Restart / CrashLoopBackOff                         |
| Deployment   | Desired Replica 미충족                                   |
| HPA          | Maximum Replica 지속 도달                                 |
| RDS          | CPU / Connection / Storage 임계값 초과 `[Threshold 확정 필요]` |
| Jenkins      | Build 실패 `[적용 여부 확정 필요]`                              |
| ArgoCD       | Application Sync / Health 실패                          |
| NAT Instance | Instance 장애 / 통신 불가                                   |

Alert는 **Grafana Alerting → Discord Webhook**을 기본 전달 경로로 사용한다.

FE / BE / AI 파트가 요구하는 Application Level Monitoring 항목은 각 파트와 협의하여 별도 관제 항목 문서로 관리한다.

---

### 7.6 미확정 IaC / Helm 입력값

Terraform 및 Helm 구성 자동화를 위해 다음 값을 추가로 확정한다.

| 구분 미확정 값   |                                        |
| ---------- | -------------------------------------- |
| IAM        | Workload별 IAM Policy                   |
| Secret     | Secrets Manager → Pod Secret 전달 방식     |
| Jenkins    | Controller Resource Request / Limit    |
| Jenkins    | PVC Size / StorageClass                |
| Jenkins    | Agent Resource / 최대 동시 Build 수         |
| ArgoCD     | Resource / Replica                     |
| Prometheus | Resource / Storage / Retention         |
| Loki       | Resource / Storage Backend / Retention |
| Grafana    | Resource / Persistence                 |
| Alloy      | Resource                               |
| Monitoring | Application Metrics Port / Path        |
| Alert      | CPU / Memory / Storage 등 Threshold     |

---

## 8. IaC 구성

### 8.1 IaC 역할 구분

인프라 및 Kubernetes 리소스는 관리 계층에 따라 **Terraform / Ansible / Helm / ArgoCD**의 역할을 분리한다.

| 도구 관리 대상 역할  |                            |                                                                                                          |
| ------------ | -------------------------- | -------------------------------------------------------------------------------------------------------- |
| Terraform    | AWS Cloud Infrastructure   | VPC, Subnet, Route Table, IGW, NAT Instance, EKS, Node Group, ECR, IAM, RDS, S3, Secrets Manager 등 프로비저닝 |
| Terraform    | KT Cloud 보조 Infrastructure | Terraform 관리 환경 및 Backup Storage `[지원 Resource 범위 확인 필요]`                                                |
| Ansible      | K8s 외부 VM 초기 설정            | NAT Instance 등 EC2 OS Level 설정 `[필요 시]`                                                                  |
| Helm         | Kubernetes Resource        | Deployment, Service, ConfigMap, HPA, Ingress, Observability/CI-CD Component 등의 패키징 및 설정                  |
| ArgoCD       | Kubernetes Resource 배포     | Git Repository의 Helm / Manifest 상태를 EKS에 동기화                                                             |
| Jenkins      | CI Pipeline                | Build, Test, Container Image 생성 및 ECR Push                                                               |

- AWS Cloud Resource는 **Terraform을 단일 Source of Truth로 관리**한다.
- Kubernetes 내부 Resource는 **Helm + ArgoCD**가 관리하며 Terraform 또는 Ansible과 관리 책임을 중복시키지 않는다.
- Ansible은 Kubernetes 내부 Resource 배포에 사용하지 않는다.
- 기존 AWS ↔ KT Cloud Tailscale Site-to-Site 구조를 사용하지 않으므로 **Tailscale Subnet Router 구성은 Ansible 관리 대상에서 제거한다.**

---

### 8.2 Terraform 관리 범위

Terraform은 다음 AWS Resource의 생성 및 변경을 담당한다.

| 영역 Terraform Resource  |                                                              |
| ---------------------- | ------------------------------------------------------------ |
| Network                | VPC, Public/WEB/WAS/DB Subnet, Route Table, Internet Gateway |
| Outbound               | NAT Instance, Elastic IP, Route                              |
| EKS                    | EKS Cluster, FE Node Group, BE·AI Node Group, EKS Add-on     |
| Registry               | ECR Repository                                               |
| IAM                    | IAM Role, IAM Policy, IRSA                                  |
| Data                   | RDS PostgreSQL, DB Subnet Group, S3                          |
| Security               | Security Group, Secrets Manager                              |
| Storage                | EBS 관련 AWS Resource `[필요 범위에 따라]`                            |
| Cache                  | ElastiCache                                                   |
| Search                 | OpenSearch                                                    |

Terraform에서 Kubernetes Application Resource를 직접 관리하지 않는다.

예를 들어 다음 Resource는 Terraform 관리 대상에서 제외한다.

- Application Deployment
- Kubernetes Service
- HPA
- ConfigMap
- Application Secret Object
- Ingress / Gateway Resource
- Prometheus / Loki / Grafana / Alloy Application 구성
- Jenkins / ArgoCD Application 구성

이러한 Kubernetes Resource는 Helm Chart로 정의하고 ArgoCD를 통해 배포한다.

---

### 8.3 Terraform 실행 환경

Terraform 코드는 Git Repository에서 관리하며, 실제 AWS 인프라의 정기적인 Open / Close 작업은 **KT Cloud에 구성한 Terraform 관리 환경**에서 수행한다.

```
Git Repository
      ↓
KT Cloud Terraform Management Environment
      ↓
Terraform init / plan / apply / destroy
      ↓
AWS API
      ↓
AWS Infrastructure

```

KT Cloud Terraform 관리 환경의 주요 역할은 다음과 같다.

- Terraform Code 실행
- 오전 AWS Infrastructure Open
- 오후 AWS Infrastructure Close
- Terraform Plan 확인
- AWS Infrastructure 생성 / 변경 / 제거

Terraform 실행 환경 자체의 세부 Resource Spec은 `[확정 필요]`이다.

AWS 인증정보를 Terraform Code, `terraform.tfvars` 또는 Git Repository에 평문으로 저장하지 않는다.

AWS 인증 방식은 `[확정 필요]`이며 IAM 최소 권한 원칙을 적용한다.

---

### 8.4 Terraform State 관리

Terraform State는 Local State가 아닌 **Remote Backend**를 사용한다.

| 항목 값             |                           |
| ---------------- | ------------------------- |
| Backend          | Amazon S3                 |
| State Bucket     | `moongcheap-tfstate`      |
| State Key        | `{env}/terraform.tfstate` |
| Region           | `ap-northeast-2`          |
| State Encryption | 적용                        |
| State Locking    | S3 Lockfile (`use_lockfile = true`) |
| State Bucket 삭제  | 일반 Destroy 대상에서 제외        |

Terraform State Bucket은 AWS Infrastructure의 재생성에 필요한 핵심 Resource이므로 일반적인 Open / Close 과정에서 삭제하지 않는다.

State Bucket은 애플리케이션 Object Storage Bucket과 분리한다.

State Locking은 별도 DynamoDB Table 없이 S3 Backend의 `use_lockfile = true` 옵션(S3 Native Locking)을 사용한다. 동시에 여러 사람이 `terraform apply`를 실행하면 먼저 Lock을 획득한 작업만 진행되고, 나머지는 Lock이 해제될 때까지 대기하거나 실패한다.

---

### 8.5 Open / Close 및 Resource 보호 정책

비용 절감을 위해 비작업 시간에는 재생성 가능한 AWS Resource를 Terraform 기반으로 종료 또는 제거한다.

이때 **Compute / Network Resource와 Stateful Resource를 명확하게 분리**한다.

| Resource 분류 일반 Close 시 정책  |                          |                            |
| -------------------------- | ------------------------ | -------------------------- |
| EKS Worker / Node Group    | 재생성 가능                   | 종료·축소 대상                   |
| EKS Cluster                | 재생성 가능                   | 비용 Runbook 정책에 따라 처리       |
| NAT Instance               | 재생성 가능                   | 종료·재생성 가능                  |
| VPC / Subnet / Route       | 재생성 가능                   | 비용 Runbook 정책에 따라 처리       |
| RDS PostgreSQL             | Stateful                 | 데이터 보호                     |
| S3 Object Storage          | Stateful                 | 유지                         |
| Terraform State S3         | IaC 핵심 데이터               | 유지                         |
| EBS / PVC 중요 데이터           | Stateful                 | 보호                         |
| ECR                        | Artifact                 | 비용 Runbook 정책에 따라 유지 여부 결정 |
| IAM / Secrets Manager      | Security / Configuration | 비용 Runbook 정책에 따라 처리       |
| KT Cloud Backup Storage    | Secondary Backup         | 유지                         |
| KT Cloud Terraform 관리 환경   | Management               | AWS Open / Close 수행을 위해 유지 |

> `terraform destroy`를 전체 Resource에 일괄 수행하지 않고, 비용 관리 Runbook에서 정의한 Open / Close 대상에 따라 Stateful Resource와 관리 Resource를 보호한다.

---

### 8.6 Terraform / Helm 책임 경계

Terraform과 Helm이 동일 Resource를 동시에 관리하지 않도록 책임 범위를 명확하게 분리한다.

```
Terraform
│
├─ AWS Network
├─ EKS Cluster / Node Group
├─ IAM / Security Group
├─ ECR
├─ RDS
├─ S3
└─ Secrets Manager

             ↓ EKS 제공

Helm + ArgoCD
│
├─ Application Deployment
├─ Service
├─ Ingress / Gateway
├─ HPA
├─ ConfigMap
├─ Jenkins
├─ ArgoCD
└─ Observability Stack

```

EKS Cluster 및 AWS Resource가 준비된 이후 Kubernetes 내부 Resource는 ArgoCD가 Git Repository의 Desired State를 기준으로 배포 및 동기화한다.

---

### 8.7 디렉토리 및 모듈 관리

Terraform Module, Environment, Helm Chart 및 ArgoCD 구성의 구체적인 Directory Structure와 Naming Convention은 **네이밍 규약서 및 Git 협업 Convention**을 따른다.

현재 AWS Architecture 기준 Terraform Module에는 최소 다음 영역이 필요하다.

```
terraform/
├─ modules/
│  ├─ vpc/
│  ├─ nat/
│  ├─ eks/
│  ├─ ecr/
│  ├─ iam/
│  ├─ rds/
│  ├─ s3/
│  ├─ secrets/
│  ├─ elasticache/
│  └─ opensearch/
│
└─ envs/
   ├─ develop/
   └─ prod/

```

ElastiCache 및 OpenSearch는 확정된 구성으로 각 Terraform Module에서 관리한다.

KT Cloud Resource를 Terraform으로 관리할 경우 AWS Terraform Module과 관리 경계를 분리한다.

---

### 8.8 미확정 IaC 입력값

실제 Terraform / Helm Code 작성 전에 다음 항목을 확정한다.

| 구분 미확정 값     |                                    |
| ------------ | ---------------------------------- |
| Terraform    | KT Cloud Terraform 관리 환경 Spec      |
| Terraform    | KT Cloud Provider로 관리할 Resource 범위 |
| Terraform    | AWS 인증 방식                          |
| Open / Close | 실제 Apply / Destroy 대상 Resource     |
| Open / Close | Resource 간 생성·삭제 순서                |
| Ansible      | NAT Instance OS 설정 필요 범위           |
| Backup       | KT Cloud Backup Resource 및 구성 방식   |
| Helm         | FE / BE / AI Resource Spec         |