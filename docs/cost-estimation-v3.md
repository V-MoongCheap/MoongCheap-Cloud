-   기존 비용 산출 런북을 확인하시려면 아래 문서 참고바랍니다.

[비용산출
(26.08.12)](https://app.notion.com/p/26-08-12-3baa1a293ff580e3a6e3d8cd8e9bd2bb?pvs=21)

[비용산출_V2
(26.08.13)](https://app.notion.com/p/_V2-26-08-13-3bba1a293ff580bc8908edc0824e62c4?pvs=21)

# 1. AWS 비용 산출

## 1. 예산

-   프로젝트 지원금: **500,000원 ≈ \$352**
    -   08/12 환율 기준
-   AWS Free-tier Credit: **\$200**
-   **AWS 가용 예산 합계: \$552**
-   프로젝트 운영 기간: **9/14 \~ 10/6, 23일**
-   Compute 운영 기준: **16시간 × 23일 = 368시간**
    -   실제 EC2 비용은 `운영시간 × 평균 실행 Node 수`로 산정한다.
-   AWS Calculator 월간 상시 운영 비용(720h): **\$730.36/month**

> `$730.36`은 월간 상시 운영 기준이며 실제 프로젝트 지출액과는 다름.

------------------------------------------------------------------------

## 2. AWS Pricing Calculator 산정 결과

현재 AWS Pricing Calculator에 입력한 값은 다음과 같다.

<https://calculator.aws/#/estimate?id=10feea9c2d726a1f13e82efdfb9d95ceee3a9244>

| 서비스 | 구성/용도 | 월 비용 |
| --- | --- | --- |
| EKS | Kubernetes Control Plane | \$73.00 |
| EC2 | NAT Instance | \$8.54 |
| EIP | NAT Instance | \$3.65 |
| S3 | Object Storage | \$8.35 |
| ECR | Container Image 100GB | \$10.00 |
| Secrets Manager | Secret 관리 | \$2.05 |
| RDS PostgreSQL | PostgreSQL + pgvector | \$161.29 |
| EC2 | FE `t3.small ×2` | \$41.61 |
| EC2 | BE/WAS `t3.large ×4` | \$310.98 |
| OpenSearch | 검색, `t3.small.search ×1` | \$42.27 |
| ElastiCache | Redis Cache | \$68.62 |
| **합계** |  | **\$730.36** |

단, 이는 프로젝트 기간 동안 리소스를 24시간 상시 운영하는 비용이 아니다.

### 2.1 산정 기준

| 구분 | 운영 기준 |
| --- | --- |
| 프로젝트 운영 기간 | **23일** |
| FE/BE/NAT Compute | **16시간 × 23일 = 368시간** |
| EKS 및 관리형 서비스 | **24시간 × 23일 = 552시간** |
| Stateful Storage | **23일간 유지** |

FE/BE Worker는 비작업 시간에 Scale-to-zero하여 EC2 Compute 비용을
절감한다.

반면 EKS Control Plane, RDS, ElastiCache, OpenSearch 등 관리형 서비스와
데이터 보존이 필요한 Storage는 프로젝트 기간 동안 유지하는 것을 기준으로
한다.

------------------------------------------------------------------------

### 2.2 서비스별 예상 비용

| 리소스 | 월간 비용 | 실제 운영 기준 | 예상 비용 |
| --- | --- | --- | --- |
| FE EC2 Compute | \$37.96 | 368h | **\$19.14** |
| FE EBS | \$3.65 | 552h | **\$2.76** |
| BE/WAS EC2 Compute | \$303.68 | 368h | **\$153.09** |
| BE EBS | \$7.30 | 552h | **\$5.52** |
| NAT Instance | \$8.54 | 368h | **\$4.31** |
| NAT Instance EIP | \$3.65 | 368h | **\$1.84** |
| EKS Control Plane | \$73.00 | 552h | **\$55.20** |
| RDS Instance | \$148.19 | 552h | **\$112.06** |
| RDS Storage 50GB | \$13.10 | 552h | **\$9.91** |
| ElastiCache (`cache.t4g.small ×2`) | \$68.62 | 552h | **\$51.89** |
| OpenSearch Instance | \$40.88 | 552h | **\$30.91** |
| OpenSearch Storage | \$1.39 | 552h | **\$1.05** |
| S3 | \$8.35 | 23일 기준 추정 | **\$6.31** |
| ECR | \$10.00 | 23일 기준 추정 | **\$7.56** |
| Secrets Manager | \$2.05 | 552h 기준 | **\$1.55** |
| **예상 합계** |  |  | **약 \$463.09** |

> S3/ECR은 실제 저장량 및 요청량에 따라 달라지므로 23일 운영을 가정한
> 예상값으로 사용한다.

------------------------------------------------------------------------

### 2.3 예산 대비 예상 사용량

| 항목 | 금액 |
| --- | --- |
| AWS 총 가용 예산 | **\$552.00** |
| 프로젝트 예상 비용 | **\$463.09** |
| **예상 잔여 예산** | **\$90.75** |
| 예상 예산 사용률 | **약 83.6%** |

현재 구성과 운영시간을 준수할 경우 **약 \$90의 비용 Buffer**를 확보할 수
있을 것으로 예상한다.

실제 비용은 데이터 전송량, S3/ECR 저장량, 로그 증가량 및 일시적인 Worker
Scale-out 등에 따라 변동될 수 있으므로 해당 Buffer는 추가 리소스 및
예상하지 못한 비용 발생에 대비하여 유지한다. 특히 **Scale-Out으로
발생하는 추가 Node-hours는 \$90.75 Buffer 내에서 우선 수용**한다.

------------------------------------------------------------------------

### 2.4 산정 시 주의사항

월간 Calculator 총액에 단순히 `368 / 730`을 적용하지 않는다.

    Compute
    FE / BE / NAT
    → 실제 가동시간 368h 기준

    Persistent / Managed
    EKS / RDS / ElastiCache / OpenSearch
    → 프로젝트 유지시간 552h 기준

    Storage
    EBS / S3 / ECR
    → 데이터 보존기간 및 실제 사용량 기준

따라서 \*\*월간 상시 운영 비용 `$730.36` → 실제 프로젝트 예상 비용 약
`$461.25`\*\*로 산정하며, 프로젝트 진행 중에는 AWS Cost Explorer의 실제
지출액을 기준으로 예상치를 지속 보정한다.

------------------------------------------------------------------------

## 3. 주요 구성 및 예상 비용

기존 설계에서 **GPU Node와 KT Cloud를 제거**하고 AWS 중심으로
재구성한다.

    FE NodeGroup
    └─ t3.small ×2

    BE/WAS NodeGroup
    └─ t3.large × N (Auto Scaling)
       ├─ BE
       ├─ AI CPU Pods
       ├─ Jenkins / ArgoCD
       └─ Observability

    RDS PostgreSQL
    ├─ Backend DB
    └─ pgvector

    ElastiCache → Redis
    OpenSearch → 검색
    S3 → Object Storage

고사양 인스턴스 소수보다 **상대적으로 작은 인스턴스를 여러 개
구성**하고, 실제 CPU/Memory 사용량에 따라 Scale-out한다. BE/WAS CPU
NodeGroup은 **`t3.large(2 vCPU / 8 GiB)`를 기본 Worker 규격으로
통일**하고, 고정된 Node 수를 유지하기보다 실제 Pod의 `requests`와 정기
작업 실행 여부에 따라 Auto Scaling으로 Node 수를 조절한다. 비용
산정에서는 기존 `t3.large ×4`를 기준 용량으로 사용하되, 실제 운영 시에는
필요한 Node만 유지하고 추가 부하 발생 시 Scale-Out하는 방식으로
운영한다.

------------------------------------------------------------------------

## 4. 실제 비용 산정 시 주의사항

월 비용 `$730.36` 전체에 `368/720`을 적용하면 안 된다.

| 구분 | 비용 처리 |
| --- | --- |
| FE/BE EC2, NAT Instance | 실제 실행시간에 따라 감소 |
| EKS | Cluster 유지시간 기준 |
| RDS | 실제 운영 방식 기준 |
| ElastiCache/OpenSearch | Domain/Cluster 유지 중 지속 과금 |
| S3/ECR/EBS/Secrets | 저장·보유 기간 동안 과금 |

따라서 `$730.36 × 368/720`은 실제 프로젝트 비용이 아니며, **서비스별
과금 특성을 분리해서 최종 비용을 계산**한다.

### 추가 비용 발생 가능성

현재 EKS Worker Node는 **t3.large(2 vCPU / 8 GiB)를 기본 규격으로
사용하고 Auto Scaling을 통해 필요한 수량을 조절**하는 것을 기준으로
비용을 산정한다. 다만 정기 작업의 동시 실행, 서비스 트래픽 증가 또는
FE·BE·AI Pod의 리소스 사용량 증가로 기존 Node에 Pod를 배치할 수 없는
경우 추가 Node가 Scale-Out되면서 **EC2 사용 시간이 증가하여 추가 비용이
발생할 수 있다.** 또한 t3.large는 Burstable Performance 인스턴스이므로
지속적인 고CPU 사용 시 CPU Credit 및 Unlimited 모드에 따른 추가 비용이
발생할 가능성이 있다. 따라서 실제 운영 및 부하 테스트를 통해 CPU·Memory
사용량과 Scale-Out 빈도를 확인하고, 필요 시 Node 수와 인스턴스 규격을
재조정한다.

------------------------------------------------------------------------

## 5. 비용 절감 방안

현재 가장 큰 비용은 **BE/WAS** **`$310.98`** **→ RDS** **`$161.29`** **→
EKS** **`$73`** **→ ElastiCache** **`$68.62`** **→ OpenSearch**
**`$42.27`** 순이다.

특히 선택 가능한 관리형 서비스는:

    ElastiCache  $68.62
    OpenSearch   $42.27
    ─────────────────
    합계        $110.89/month

예산이 부족할 경우

1.  **Redis/OpenSearch를 EKS Pod로 자체 호스팅**하는 방안을 우선
    비교한다.
2.  FE Pod 대신 Vessel을 이용해 FE 호스팅을 검토한다.

또한 EC2는 비작업 시간 종료, RDS는 최소 사양 유지, S3/ECR은 Lifecycle
Policy를 적용한다.

------------------------------------------------------------------------

## 6. 최종 기준

-   **월간 상시 운영 Baseline:** `$730.36`
-   **AWS 총 가용 예산:** `$552`
-   **실제 Compute 운영:** `368시간`
-   **OpenSearch/ElastiCache:** 관리형 서비스와 EKS 자체 호스팅 비용
    비교
-   **Worker:** 실제 Pod `requests/limits` 및 모니터링 결과에 따라 조정

### 인프라 우선순위

1.  **기한 내 안정적인 서비스 완성**
2.  **\$552 예산 초과 방지**
3.  **비용 절감을 위한 불필요한 Teardown 최소화**

------------------------------------------------------------------------

# AWS 리소스 스펙 선정 근거

## 1. 선정 기준

리소스 스펙은 단순히 최소 비용을 기준으로 선정하지 않고 다음 세 가지를
함께 고려하였다.

**① 실제 애플리케이션 요구량 → ② 장애 발생 시 영향 범위 → ③ \$552 예산**

또한 고사양 Instance 1개에 워크로드를 집중하기보다 **상대적으로 작은
Instance를 2개 이상 배치하여 Kubernetes에서 워크로드를 분산**하는
방향으로 변경하였다.

------------------------------------------------------------------------

## 2. FE Worker --- `t3.small ×2`

### FE팀 분석 결과

FE팀에서 현재 애플리케이션을 분석한 결과:

| 항목 | 확인 결과 |
| --- | --- |
| 전체 Route | **16개** |
| 정적 Route | **14개** |
| 기존 예상 FE Pod | 약 **0.5 vCPU / 1GiB** |
| `public/images` | **104개 / 약 41MB** |
| 최대 문제 이미지 | **850 × 32,768 / 11.9MB** |
| 해당 이미지 처리 시 Memory | 약 **110MB** |
| 이미지 최적화 후 | **약 41MB → 2MB** |

기존에는 Next.js Runtime 이미지 최적화 과정에서 CPU/Memory 사용량 증가
가능성이 있었지만, **이미지를 사전에 Resize/WebP 변환**하기로 하면서 FE
Runtime에서 높은 Compute 성능이 필요할 가능성이 낮아졌다.

기존 설계의 `t3.large`는 2 vCPU / 8GiB인데 FE Pod 예상치가 약 0.5 vCPU /
1GiB였기 때문에 **약 1\~1.5 vCPU / 6\~7GiB가 남는 과한 구성**이었다.

### 그래서 왜 `t3.small ×2`인가?

`t3.small`은:

    2 vCPU / 2GiB

이므로 두 대를 사용하면 총:

    t3.small ×2
    = 4 vCPU / 4GiB

를 확보한다.

단일 `t3.large`보다 총 Memory는 작지만 FE 자체의 Memory 요구량이
낮아졌고, **Node를 2개로 분리하여 FE Pod Replica를 분산할 수 있다는
장점**이 있다.

기존 설계에서도 FE HA의 목적은 단일 Pod/Node 장애 시 서비스 전체가
영향을 받는 것을 방지하는 것이었다.

**결론**

> FE는 정적 페이지 중심이며 이미지 Runtime 부하도 제거할 예정이므로
> 고메모리 Instance가 필요하지 않다. 따라서 `t3.large ×1` 대신
> \*\*`t3.small ×2`\*\*로 구성하여 비용과 분산 배치를 함께 고려한다.

------------------------------------------------------------------------

## 3. BE/WAS Worker --- `t3.large × N`

BE/WAS Node에는 Backend만 올라가는 것이 아니다.

    BE
    AI API
    AI Embedding
    Jenkins
    ArgoCD
    Prometheus
    Grafana
    Loki
    Alloy
    Kubernetes Add-on

등이 함께 동작한다.

기존 BE 요구사항은 최소 **4 vCPU / 8GiB** 수준으로 잡혀 있었고, 기존
`t3.xlarge`는 **4 vCPU / 16GiB**라 BE만으로 CPU 여유가 거의 없다고
분석했었다.

GPU Node를 제거하면서 AI 워크로드까지 CPU Worker로 들어오기 때문에
현재는 BE 전용 Node라기보다 **WAS/AI/System 통합 CPU Node Pool**에
가깝다.

### 후보 비교

| 항목 | 기준 |
| --- | --- |
| 기본 Worker | `t3.large` |
| Node당 Resource | 2 vCPU / 8 GiB |
| 운영 방식 | Auto Scaling |
| 평시 | 필요한 최소 Node 유지 |
| 부하 증가 | 추가 `t3.large` Scale-Out |
| 정기 작업 | 필요 시 사전 Scale-Out |
| 작업 종료 | 유휴 Node Scale-In |
| 비용 산정 기준 | 최대 `t3.large ×4` 기준 |

| 구성 | 총 vCPU | 총 Memory | 판단 |
| --- | --- | --- | --- |
| `t3.medium ×4` | 8 | 16GiB | Memory 부족 가능성 |
| `t3.large ×3` | 6 | 24GiB | CPU 여유 부족 가능성 |
| **`t3.large ×4`** | **8** | **32GiB** | **선정** |
| `t3.xlarge ×2` | 8 | 32GiB | 총량은 동일하나 Node 수 감소 |

여기서 `t3.large ×4`와 `t3.xlarge ×2`는 총량만 보면 똑같다.

    t3.large ×4
    = 8 vCPU / 32GiB

    t3.xlarge ×2
    = 8 vCPU / 32GiB

하지만 한 Node 장애 시:

    t3.large ×4 → 전체 Capacity의 25% 손실

    t3.xlarge ×2 → 전체 Capacity의 50% 손실

이므로 여러 Node로 분산하는 현재 설계 방향에는 `t3.large ×4`가 더
적합하다.

또 Jenkins Dynamic Agent처럼 일시적으로 리소스를 사용하는 Pod와 BE/AI
Pod를 서로 다른 Node에 배치하기도 쉽다.

**결론**

> 동일한 8 vCPU / 32GiB를 확보하면서 장애 영향 범위와 Kubernetes
> Scheduling 유연성을 높이기 위해 BE/AI/System 워크로드는
> `t3.large(2 vCPU / 8 GiB)`를 CPU Worker의 기본 단위로 사용한다. Node
> 수를 `×4`로 고정하지 않고 실제 Pod의 `requests`와 부하에 따라 Auto
> Scaling하며, 정기 작업처럼 실행 시점을 예측할 수 있는 워크로드는 필요
> 시 사전에 Scale-Out한다. 비용 산정에서는 최대 `t3.large ×4` 운영을
> 기준으로 예산을 확보하고, 실제 운영에서는 필요한 Node만 유지하여
> Compute 비용을 절감한다.

단, 개별 Pod의 `requests`가 `t3.large` 한 대의 Allocatable Resource보다
크면 해당 Pod는 Scheduling할 수 없으므로 **BE/AI 최종 Pod Spec 확인 후
확정**한다.

------------------------------------------------------------------------

## 4. RDS PostgreSQL --- Multi-AZ / 50GB

RDS는 FE/BE Worker와 다르게 단순히 비용만 보고 최소 구성으로 내리지
않았다.

    RDS PostgreSQL
    ├─ Backend Transaction Data
    └─ AI Vector Data
        └─ pgvector

즉 **서비스의 원본 데이터와 Vector 데이터가 모두 들어가는 Stateful 핵심
리소스**다.

기존 KT Cloud 구조를 제거하면서 DB도 AWS 내부로 이전했기 때문에 네트워크
구조도 단순해지고 AWS 내부에서 EKS와 직접 통신할 수 있게 되었다.

### 왜 RDS인가?

EC2에 PostgreSQL을 직접 구성하면 비용은 줄일 수 있지만:

-   장애 복구
-   Backup
-   DB 운영
-   Patch
-   Storage 관리

등을 인프라팀이 직접 담당해야 한다.

프로젝트 우선순위가 \*\*"비용 최소화"보다 "기한 내 안정적인 서비스
완성"\*\*이므로 DB는 관리형 RDS를 유지한다.

### 왜 Multi-AZ인가?

Worker Node는 장애가 발생해도 Kubernetes가 Pod를 다른 Node에 재배치할 수
있지만 DB는 그렇지 않다.

따라서 **애플리케이션 Compute는 작은 Node를 여러 개 두고, DB는
Multi-AZ로 장애 대응 능력을 확보**하는 식으로 HA 수준을 다르게 적용한다.

### 왜 50GB인가?

Backend 데이터뿐 아니라 `pgvector`의 Embedding 데이터도 동일
PostgreSQL에 저장된다.

따라서 최소 Storage만 배정하기보다 **50GB를 초기 여유 용량으로
확보**하고 실제 사용량을 모니터링한다.

**결론**

> DB는 전체 서비스의 Stateful 핵심 리소스이므로 Compute Worker보다
> 안정성을 우선하여 **RDS PostgreSQL + Multi-AZ + 50GB**로 구성한다.

------------------------------------------------------------------------

## 5. NAT Instance --- `t3a.micro ×1`

NAT는 성능 요구보다 **NAT Gateway 비용 절감**이 선정 이유가 명확하다.

기존 계산:

| 구성 | 비용 |
| --- | --- |
| NAT Gateway | 약 **\$178.18/month** |
| `t3a.micro` NAT Instance | 약 **\$8.54/month** |
| 차이 | **약 \$170/month 절감** |

실제 16시간 × 23일 기준 NAT Instance Compute 비용은 기존 계산에서 약
**\$4.31** 수준이었다. (EIP +\$1.84)

따라서 개발/통합 프로젝트에서 NAT Gateway 수준의 관리형 HA보다 비용
절감을 우선하여 `t3a.micro ×1`을 사용한다.

------------------------------------------------------------------------

## 6. OpenSearch --- `t3.small.search ×1`

OpenSearch는 상품명/설명/카테고리 등 **서비스 검색 Index** 용도로
검토한다.

처음 Calculator 기본값에 가까운 `r5.2xlarge.search`는:

    8 vCPU / 64GiB

였고 Dedicated Master `×3`, UltraWarm `×2`까지 포함했을 때 Calculator가
**\$7,209.48/month**까지 나왔다.

현재 프로젝트 규모에는 명백한 Over-spec이므로 최소 개발 구성으로 낮췄다.

    t3.small.search ×1
    gp3 10GB

    Dedicated Master X
    UltraWarm X
    Cold Storage X

그 결과 현재 Calculator 기준:

> **\$42.27/month**

까지 감소했다.

따라서 현재 OpenSearch 구성은 **Production HA 목적이 아니라 개발/통합
환경에서 검색 기능을 제공하기 위한 최소 구성**이다.

------------------------------------------------------------------------

## 7. ElastiCache --- Redis

ElastiCache도 처음 검토한 Serverless 구성에서는:

    Cache Data: 1GB
    Request: 10 req/s
    Transfer: 1KB/request

기준으로 Calculator가 약:

> **\$127.86/month**

까지 나왔다.

우리 프로젝트 규모에서 Cache 하나에 이 비용을 사용하는 것은 부담이
크다고 판단하여 **Node-based Redis 최소 구성**으로 변경했다.

현재 Calculator 비용:

> **\$68.62/month**

Redis는 BE의 Session/Cache 요구사항을 반영하여 **Amazon ElastiCache로
확정**한다. 예산이 부족한 경우에는 EKS 내부 Redis Pod 자체 호스팅으로
전환하는 방안을 비용 절감 대안으로 비교한다.

------------------------------------------------------------------------

## 8. 최종 선정 요약

| 리소스 | 선정 스펙 | 핵심 선정 근거 |
| --- | --- | --- |
| **FE Worker** | `t3.small ×2` | 14/16 정적 Route + 이미지 41→2MB 최적화 + Node 분산 |
| **BE/WAS Worker** | `t3.large ×N` | **8 vCPU / 32GiB**, 작은 Node 분산 및 AI/System Pod 수용 |
| **RDS** | PostgreSQL / **Multi-AZ / 50GB** | 핵심 Stateful 리소스 안정성 + pgvector 통합 |
| **NAT** | `t3a.micro ×1` | NAT GW 대비 월 약 **\$170 절감** |
| **OpenSearch** | `t3.small.search ×1` | 개발용 최소 구성, **\$7,209 → \$42.27** |
| **ElastiCache** | Node-based Redis | Serverless **\$127.86**보다 비용 절감 |
| **S3** | S3 Standard | Object Storage를 Compute와 분리 |
| **ECR** | 100GB | FE/BE/AI Container Image 저장 |
