> 작성: 인프라팀 부학성, 양재혁 · 상태: **실제 프로젝트 적용 초안**
>
> 참고 문서: `비용산출(08/12)`, `비용산출_V2(08/13)`,
> `비용산출_V3(09/09)`, `인프라·HA·비용 차별화 전략 문서_최종`,
> `타 팀 요청사항`, `프로젝트 계획서`

------------------------------------------------------------------------

## 1. 개요

-   **목적**: 제한된 예산(50만원 + 클라우드 크레딧) 안에서 프로젝트를
    완주하기 위한 비용 관리 기준과 운영 원칙을 정리
-   **범위**: AWS 계정(공용 1개) 사용 전체
-   **갱신 주기**: 매주 스크럼 때 실제 사용량 반영해서 업데이트

------------------------------------------------------------------------

## 2. 예산 현황

기존 KT Cloud Credit 항목을 제거한다.

| 항목 | 금액 | 비고 |
| --- | --- | --- |
| 프로젝트 지원금 | 50만원 ≈ **\$352** | 08/12 환율 기준 |
| AWS Free-tier Credit | **\$200** |  |
| **AWS 측 가용 크레딧 합계** | **≈ \$552** |  |
| 도메인 구매비 | 약 1,500원 | 사용 시 별도 실비 |

-   AWS 중심의 단일 Cloud 구조로 변경
-   집중 운영기간: **9/14 \~ 10/6, 23일**
-   Compute 비용 산정 기준: **16시간 × 23일 = 368시간**

------------------------------------------------------------------------

## 3. 운영 계정 방식

-   AWS 계정은 **인프라팀이 신규 생성한 계정 1개를 관리**하며, 콘솔
    로그인 자격 증명은 인프라팀만 보유하고 **타 팀과 공유하지 않는다**
-   타 팀에는 계정이나 로그인 정보 대신 **엔드포인트/접속 URL 등
    결과물**을 접속 매뉴얼로 전달한다 (11장 참고)
-   **팀별 IAM 계정은 별도로 발급하지 않으며**, 타 팀이 AWS
    Console/API에 직접 접근해야 하는 경우가 생기면 공유 계정 로그인
    정보 대신 **필요 최소 권한의 IAM Role**을 발급하는 방식으로
    검토한다

### 이 방식에서 생기는 리스크 & 보완 원칙

| 리스크 | 보완 원칙 |
| --- | --- |
| 누가 무엇을 만들고 지웠는지 추적 어려움 | 리소스는 **Terraform apply/destroy로만** 생성·삭제(콘솔에서 임의 생성·삭제 금지 원칙), 커밋/PR로 변경 이력 추적 |
| 실수로 고비용 리소스가 켜진 채 방치될 가능성 | Budget Alert + 주간 Cost Explorer 점검 (12장 참고) |
| 계정 정보 유출 시 전체 리소스 노출 | 콘솔 로그인 정보는 필요 인원(인프라팀)만 보유, 타 팀에는 접속 정보 대신 **엔드포인트/접속 URL 등 결과물만 전달** (11장 참고) |
| 고비용 리소스를 아무나 생성 가능 | 10장 "리소스 생성 규칙" 참고 --- 사전 협의 후 생성 원칙 |

------------------------------------------------------------------------

## 4. 확정된 아키텍처 요소

| 항목 | 변경 내용 | 비용 영향 |
| --- | --- | --- |
| **GPU** | GPU Node 미사용, AI도 CPU Pod로 운영 | 기존 GPU 비용 제거 |
| **Worker** | FE `t3.small × 2`(Managed Node Group), BE/WAS `t3.large × N`(**Karpenter**, 0~4) | 작은 Node 다중 구성, BE/WAS는 Pod 없으면 0대 |
| **DB** | **AWS RDS PostgreSQL, Multi-AZ, 50GB** | KT Cloud DB 제거, RDS 비용 발생 |
| **Vector DB** | PostgreSQL에 `pgvector` 적용 | 별도 Vector DB 불필요 |
| **Object Storage** | **Amazon S3** | KT Cloud Object Storage 제거 |
| **Redis** | Amazon ElastiCache | 약 \$68.62/month |
| **검색** | Amazon OpenSearch Service | 약 \$42.27/month |
| **AWS↔KT 연결** | 제거 | Tailscale 불필요 |
| **ALB** | 미사용, Cloudflare Tunnel 사용 | ALB 비용 제거 |
| **NAT** | `t3a.micro` NAT Instance | NAT Gateway 대비 비용 절감 |

------------------------------------------------------------------------

## 5. NAT Instance 기종 선정 및 비용 계산 (서울 리전 On-Demand 기준)

### 5.1 기종 선정

NAT 역할만 수행하면 되므로 상시 고성능이 필요 없고, 저렴하면서 충분한
네트워크 대역폭(최대 5Gbps)과 최소한의 메모리 여유가 있는 인스턴스면
충분합니다.

| 후보 | vCPU / 메모리 | 서울 리전 On-Demand | 평가 |
| --- | --- | --- | --- |
| t4g.nano / t3.nano | 2 vCPU / 약 0.5GiB | \$0.0052\~0.0065/h | 가장 저렴하지만 0.5GiB는 다수 팀원이 동시에 이미지 pull·apt·terraform provider 다운로드 등을 할 때 커넥션 트래킹(conntrack) 여유가 부족할 수 있음 |
| **t3a.micro (선정)** | 2 vCPU / 1GiB | **\$0.0117/h (확인됨)** | 나노 대비 메모리 2배로 다수 동시 연결에 여유, AMD 기반이라 t3 대비 저렴, 버스터블 크레딧으로 순간 트래픽도 대응 가능 |
| t3.micro | 2 vCPU / 1GiB | 약 \$0.013/h (추정) | t3a.micro와 스펙 동일하나 소폭 더 비쌈 |
| t4g.micro | 2 vCPU / 1GiB | 약 \$0.0104/h (추정) | t3a.micro와 유사하게 저렴하나, ARM이라 NAT Instance AMI(주로 x86 기반 배포판) 호환성을 별도 확인해야 함 |

**→ 선정:** **`t3a.micro`** (2 vCPU / 1GiB, 서울 리전 On-Demand
**\$0.0117/시간**)

-   이유: 메모리 여유(1GiB)로 팀 전체 트래픽을 안정적으로 처리, x86
    기반이라 표준 NAT AMI/Amazon Linux 호환성 문제 없음, nano 대비
    시간당 차액은 한 달에 약 \$4 수준이라 안정성 대비 부담 없음
-   운영 시 필요 조치: **소스/대상 확인(Source/Dest Check) 비활성화**,
    **Elastic IP 연결**(Public IPv4 주소는 시간당 별도 과금), Private
    Subnet Route Table의 default route를 NAT Instance ENI로 지정, 장애
    시 Terraform으로 재생성 가능하도록 스크립트화
-   **[2026-09-17 이력]** 최초 apply 당시 AWS 계정이 **Free Tier 상태**여서
    `t3a.micro`가 `InvalidParameterCombination: not eligible for Free Tier`로
    생성 거부됐고, NAT가 없어 FE Node가 ECR에 못 나가 EKS Node Group이
    30분 가까이 대기했다. 기종을 낮추지 않고 **결제수단 등록으로 계정
    제약을 해제**해 해결했다. 계정을 새로 만들거나 바꾸면 이 조건을 먼저
    확인할 것(Bootstrap Runbook §0.0, `docs_troubleshooting/…-05-*.md`).
-   재생성 절차: NAT Instance는 ENI·EIP와 분리돼 있어(`modules/nat`)
    `terraform apply -replace=module.nat.aws_instance.nat`로 인스턴스만
    교체하면 라우팅·EIP는 유지된다.

### 5.2 NAT Instance 비용

| 항목 | 24시간 상시 가동 | 16시간×23일 가동 (9/14\~10/6 가정) |
| --- | --- | --- |
| t3a.micro 인스턴스 | \$0.0117 × 730h ≈ **\$8.54/월** | \$0.0117 × 368h ≈ **\$4.31** |
| EBS(gp3, 8GB 기본) | 무시할 수준 (\< \$1/월) | 무시할 수준 |
| Elastic IP | \$3.65 | **\$1.84** |
| 데이터 전송(아웃바운드) | NAT Gateway의 GB당 처리 요금(\$0.045/GB) 없음. 일반 EC2 인터넷 아웃바운드 요금만 적용(월 100GB까지 무료 구간 존재) | 좌동 |

기존 산출(08/13)에서 "VPC/NAT" 항목이 월 \$178.18(NAT Gateway
기준)이었던 것과 비교하면, NAT Instance(t3a.micro) 전환으로 **월 약
\$170 절감**됩니다.

------------------------------------------------------------------------

## 6. 전체 비용 구조 (서울 리전, AWS 단일 Cloud 구성 반영)

## 6.1 AWS 월별 비용

현재 AWS Pricing Calculator 기준:

| 서비스 | 구성 | 월 비용 |
| --- | --- | --- |
| Amazon EKS | EKS Control Plane | \$73.00 |
| EC2 | NAT Instance `t3a.micro` | \$8.54 |
| EIP | NAT Instance Public IPv4 | \$3.65 |
| S3 | Object Storage | \$8.35 |
| ECR | Container Image 100GB | \$10.00 |
| Secrets Manager | Secret 관리 | \$2.05 |
| RDS PostgreSQL | **Multi-AZ / 50GB / pgvector** | \$161.29 |
| EC2 FE | **`t3.small ×2`** | \$41.61 |
| EC2 BE/WAS | **`t3.large ×4`** | \$310.98 |
| OpenSearch | `t3.small.search ×1` | \$42.27 |
| ElastiCache | Redis | \$68.62 |
| **합계** |  | **\$730.36/month** |

> `$730.36`은 Public IPv4(EIP) 비용을 포함한 월간 상시 운영 Baseline이며
> 실제 프로젝트 지출액과 동일하지 않다. `BE/WAS t3.large ×4`는 비용
> 산정을 위한 기준 용량이며, 실제 운영에서는 **Karpenter**가 `t3.large`를
> 기본 Worker 규격으로 Pod의 `requests` 및 부하에 따라 Node 수를 0~4대
> 사이에서 조정한다(NodePool `limits`가 상한).

## 6.2 실제 가동 패턴

Compute 운영시간은 다음을 기준으로 한다.

    16시간 × 23일 = 368시간

단, 기존 문서처럼 전체 월 비용에 `368/730`을 적용하지 않는다.

| 비용 유형 | 대상 | 관리 방식 |
| --- | --- | --- |
| Compute | FE/BE EC2, NAT Instance | 실제 실행시간 기준 |
| Control Plane | EKS | Cluster 유지시간 기준 |
| 관리형 서비스 | RDS, ElastiCache, OpenSearch | 실제 리소스 유지기간 기준 |
| Storage | S3, EBS, ECR | 저장량 및 보유기간 기준 |
| Secret | Secrets Manager | Secret 보유량 기준 |

따라서 실제 비용은 **Compute + 관리형 서비스 + Storage 비용을 분리하여
추적**한다.

## 6.3 System Add-on 배치

기존의 FE/BE/AI/GPU Node별 여유 Capacity 계산은 삭제한다.

현재는 `[개정 2026-09-18, DEC-1]`:

    System NodeGroup (Managed) — 컨트롤러 고정 노드, BE·AI(WAS) Subnet
    └─ t3.medium ×2
       ├─ ArgoCD
       ├─ Karpenter Controller
       └─ (기타 클러스터 컨트롤러)

    FE NodeGroup (Managed)
    └─ t3.small ×2

    BE/WAS (Karpenter NodePool)
    └─ t3.large × N (0 ≤ N ≤ 4)
       ├─ BE
       ├─ AI CPU Pods
       ├─ Jenkins
       └─ Observability

로 운영한다. System NodeGroup은 Karpenter가 자기 자신을 띄울 수 없기
때문에 필요하며(컨트롤러가 Karpenter 노드에 있으면 노드 회수 시 컨트롤러도
같이 사라짐), Open/Close 시 FE와 같은 방식으로 `desired_size` 0↔2로
관리한다(7.1). 비용 표(4장·6.1)의 반영은 설계서 4.2 개정과 함께 한다.

`BE/WAS t3.large ×4`는 비용 산정을 위한 기준 용량이며, 실제 운영에서는
Karpenter가 `t3.large`를 기본 Worker 규격으로 Pod의 `requests` 및 부하에
따라 Node 수를 조정한다. Karpenter Node는 Terraform State 밖이므로 **Close
시 Node Group `desired_size`로는 끌 수 없고**, MGMT 서버가 System·FE Node
Group을 0으로 내린 뒤(Karpenter 컨트롤러 종료) `karpenter.sh/nodepool`
태그가 붙은 EC2를 직접 종료한다. Open 시에는 Pod 수요에 따라 Karpenter가
다시 띄운다(절차는 7.1).

~~System Add-on을 위한 별도 전용 Node는 초기에는 생성하지 않고~~ →
`[개정 2026-09-18]` DEC-1로 System NodeGroup(t3.medium ×2)을 두기로 확정.
BE/WAS 워크로드 Node 부족 시에는 Karpenter가 `t3.large` 단위로 Scale-out한다.

------------------------------------------------------------------------

## 7. 일정별 비용 관리 계획

| 기간 | 단계 | 비용 관리 포인트 |
| --- | --- | --- |
| **9/7\~9/13** | 핵심 인프라 구축 | VPC/EKS/NodeGroup/NAT/ECR/RDS 등 구축 |
| **9/14\~9/20** | 서비스 이관 | FE/BE/AI CPU 워크로드 배포 |
| **9/21\~9/27** | 통합 테스트 | 전체 서비스 운영, 실제 CPU/Memory 측정 |
| **9/28\~10/6** | Final | 리허설/발표에 필요한 리소스 유지, 종료 후 정리 |

### 7.1 야간/주말 운영 `[개정 2026-09-18]`

> **비작업 시간 리소스 운영**
>
> -   KT Cloud MGMT 서버의 cron이 **AWS CLI로 Compute만 켜고 끈다**
>     (`terraform/scripts/mgmt/{open,close}-infra.sh`). Terraform
>     `apply/destroy`는 Open/Close에 쓰지 않으며, 인프라 생성·변경 시
>     인프라 담당자가 로컬에서 수동으로 수행한다.
> -   담당: **정 최상우 / 부 양재혁**
> -   평일: **09:00\~22:00** 기본 운영
> -   추가 작업 요청 시: **익일 01:00까지 연장**
> -   주말: 각 파트 작업 요청을 받아 **12:00\~익일 01:00 범위 내 필요한
>     시간만 운영**
> -   추석 연휴: 작업 요청이 있는 날만 **09:00\~22:00 운영**
> -   RDS/S3/EBS/ElastiCache/OpenSearch 등 Stateful·관리형 Resource는
>     Close 대상에서 제외한다(스크립트가 건드리지 않음).

**Close가 하는 일 (순서대로)** — 역순이 Open

| 순서 | 대상 | Close | Open | 방식 |
| --- | --- | --- | --- | --- |
| 1 | Managed Node Group — `system-ng`(컨트롤러, t3.medium ×2) · `fe-ng`(FE, t3.small ×2) | `desired_size` 0 | `desired_size` 2 (system → fe 순) | `eks update-nodegroup-config` (Terraform `*_min_size=0`, `desired_size`는 `ignore_changes` — system-ng 생성 시(S-1) 동일 적용 필요) |
| 2 | BE·AI Karpenter 노드 | EC2 종료 (`karpenter.sh/nodepool` 태그로 조회) | 없음 — Pod 수요가 생기면 Karpenter가 다시 띄움 | `ec2 terminate-instances`. Karpenter 컨트롤러가 system-ng와 함께 내려간 뒤라 재프로비저닝 안 됨 |
| 3 | NAT Instance | `stop` | `start` (노드보다 먼저) | `ec2 stop/start-instances`. ENI·EIP가 분리돼 있어 IP·라우트 유지 |

**Open 후 확인 항목** — 순서대로, 앞이 안 되면 뒤는 볼 필요 없음. Envoy·cloudflared·Route는 전부 system-ng 위라 별도 Open 조치는 없지만, **Gateway `Programmed=True`만으로 "열림"으로 판단하지 않는다**(Gateway가 준비돼도 개별 HTTPRoute는 `Accepted`·`ResolvedRefs`가 따로 평가되며, backend Service가 없으면 `Accepted=True / ResolvedRefs=False`로 외부는 404·5xx).

```bash
# 1) 노드
kubectl get node -l workload=system                                   # 2대 Ready
# 2) Gateway
kubectl -n infra get gateway moongcheap-gateway \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'   # Accepted=True, Programmed=True
kubectl -n infra get svc -l gateway.envoyproxy.io/owning-gateway-name=moongcheap-gateway   # TYPE=ClusterIP (LoadBalancer면 8.5 위반)
# 3) HTTPRoute — 모든 Route가 Accepted=True 그리고 ResolvedRefs=True, parentRef가 infra/moongcheap-gateway
kubectl get httproute -A \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,HOSTS:.spec.hostnames[*],ACCEPTED:.status.parents[0].conditions[?(@.type=="Accepted")].status,RESOLVED:.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status,PARENT:.status.parents[0].parentRef.name'
# 4) cloudflared
kubectl -n infra get deploy cloudflared                                # 2/2 Ready
kubectl -n infra logs deploy/cloudflared --tail=20 | grep -c 'Registered tunnel connection'   # ≥ 1 (보통 4)
# 5) Host별 smoke test — 클러스터 안에서 Envoy로 직접(도메인·Cloudflare 무관)
for h in moongcheap.shop api.moongcheap.shop jenkins.moongcheap.shop grafana.moongcheap.shop argocd.moongcheap.shop; do
  printf '%-28s ' "$h"; kubectl -n infra run curl-$RANDOM --rm -i --restart=Never --image=curlimages/curl -q -- \
    curl -s -o /dev/null -w '%{http_code}\n' -H "Host: $h" http://moongcheap-envoy.infra.svc.cluster.local/
done                                                                   # 200/301/302/401(Access) 정상, 404=Route 없음, 503=backend 없음
# 6) 외부(도메인 apply 후) — Cloudflare Access 뒤 호스트는 302/403이 정상
curl -sI https://moongcheap.shop | head -1
```

| 증상 | 원인 | 확인 |
|---|---|---|
| 3)에서 `ResolvedRefs=False` | backendRef Service 이름/ns/port 불일치 | `kubectl -n <ns> get svc` 와 HTTPRoute `backendRefs` 대조 |
| 3)에서 `Accepted=False` | parentRef ns 불일치 또는 Gateway listener `allowedRoutes` | `gateway.spec.listeners[].allowedRoutes.namespaces.from=All` |
| 5)에서 404 | 해당 Host의 HTTPRoute 없음 / hostnames 오타 | 3)의 HOSTS 열 |
| 5)에서 503 | Route는 있는데 backend Pod 없음(Close 직후 BE·AI 노드 미기동 등) | `kubectl -n <ns> get endpoints <svc>` |
| 6)만 530/502 | cloudflared 미기동 또는 토큰 | 4) |

**Close 상태에서도 계속 나가는 비용**: EKS Control Plane + RDS + ElastiCache + OpenSearch ≈ **$345/월**(6.1). Close로 줄어드는 것은 Node(FE·BE·AI) + NAT 실행 시간분이다.

**스케줄 변경 방법**: `terraform/scripts/mgmt/schedule.csv`(형식 `action,time,days,enabled,memo` — 예 `open,09:00,mon-fri,true,평일 운영 시작`)를 고쳐 `develop`에 머지하면 MGMT 서버가 5분 이내에 crontab을 갱신한다. **당일 변경도 반영된다** — 변경 전후 CSV로 계산한 "지금 있어야 할 상태"(직전 이벤트가 open인지 close인지)가 달라지면 `reconcile.sh`가 즉시 그 상태로 맞춘다(예: 토요일 열려 있는 중에 `close,15:00,sat`를 15:03에 머지 → 15:05 안에 닫힘). 기대 상태가 안 바뀌는 변경(평일 시각 조정 등)은 다음 cron 시각부터 적용되고 현재 상태는 건드리지 않으므로, 수동 연장 운영 중에도 안전하다. 임시 연장(익일 01:00 등)은 MGMT 서버에서 `open-infra.sh`/`close-infra.sh`를 수동 실행한다. MGMT 서버가 꺼져 있어 cron을 놓쳤으면 `reconcile.sh`를 수동 실행해 복구한다. MGMT 서버 초기 설정과 IAM 최소 권한은 `V-MoongCheap/docs/2026-09-18-mgmt-server-setup-guide.md`, 정책 JSON은 `terraform/scripts/mgmt/mgmt-iam-policy.json`.

**주의**: `schedule.csv` PR은 머지 즉시 노드를 내릴 수 있다 — close를 앞당기는 변경은 머지 시각을 팀에 알린다. Close는 drain 없이 노드를 내리므로 실행 중인 Pod는 즉시 종료된다. Jenkins 빌드·배치 작업은 Close 시각 전에 끝나야 한다. BE·AI EBS PVC는 AZ 고정이라 Open 후 다른 AZ에 노드가 뜨면 해당 Pod가 Pending에 걸릴 수 있다(설계서 4.4·7.2 — AZ 정책 [확정 필요]).

------------------------------------------------------------------------

## 8. Redis(ElastiCache) 처리 방안

| 서비스 | 관리형 구성 | 월 비용 | 비용 절감 대안 |
| --- | --- | --- | --- |
| **Redis** | Amazon ElastiCache | **\$68.62** | Redis Pod on EKS |
| **OpenSearch** | `t3.small.search ×1` | **\$42.27** | OpenSearch Pod on EKS |
| **합계** |  | **\$110.89** |  |

현재 Calculator에는 두 관리형 서비스를 모두 포함한다.

다만 실제 예산이 부족하거나 기존 BE/WAS Worker Capacity에서 수용할 수
있다면 EKS 자체 호스팅을 검토한다.

자체 호스팅 전환 시에는 **관리 부담 + EBS 비용 + Worker 증설 비용**까지
포함하여 관리형 서비스와 비교한다.

### 권장 운영 규칙

1.  기본값은 확정 구성인 관리형 서비스(Amazon ElastiCache / OpenSearch)로
    운영한다.
2.  Week 2 종료 시점(9/20 전후)에 실제 비용 소진율을 확인 → Cost
    Explorer 기준 예산의 80% 이상 사용 중이면 EKS 자체 호스팅(Redis Pod /
    OpenSearch Pod)으로 전환을 검토한다.
3.  전환하더라도 Redis가 실제로 어떤 기능(Session/Cache/PubSub)에
    쓰이는지를 먼저 BE팀에게 확인 (13장 Action Item)

------------------------------------------------------------------------

## 9. 비용 절감 운영 원칙

-   **NAT Instance(t3a.micro) 사용**, 장애 시 Terraform으로 재생성 절차
    문서화
-   **ALB 미사용**, Cloudflare Tunnel + Envoy Gateway(Gateway API, ClusterIP)로 대체
-   **On-Demand 우선 운영**, Spot은 서비스 완성 후 부하 테스트 결과를
    보고 별도 검토
-   **ECR 이미지 정리 정책** 적용
-   고사양 Worker Scale-up보다 **작은 Worker Scale-out 우선**
-   RDS는 핵심 Stateful Resource이므로 **Multi-AZ 유지**
-   ElastiCache/OpenSearch는 예산 부족 시 **EKS 자체 호스팅 비교**
-   Prometheus/Loki Retention 관리
-   **비용 태그 표준화**

```{=html}
<!-- -->
```
      Project = MoongCheap
      Environment = develop | prod
      ManagedBy = Terraform
      Service = backend | ai | observability | infra
      Owner = cloud

------------------------------------------------------------------------

## 10. 리소스 생성·삭제 운영 규칙

| 규칙 | 내용 |
| --- | --- |
| 생성/삭제 방식 | PR로 승인된 Open / Close 대상에 대해서만 Terraform `apply/destroy` 수행 (인프라팀만 수행). **전체 Resource 일괄 `destroy` 금지** |
| 스펙 변경 | 실제 CPU/Memory/Latency Metric 확인 후 변경 |
| 고비용 서비스 추가 | 비용 증가분 계산 후 팀 협의 |
| Stateful/관리 리소스 보호 | **RDS, S3, EBS/PVC, ElastiCache, OpenSearch, Terraform State S3, KT Cloud Backup Storage, IAM, Secrets Manager는 일반 Compute Close/Destroy 대상에서 제외** |
| 일시적 Scale-up | 테스트 종료 후 기존 Baseline으로 원복 |
| 도메인 갱신 | 프로젝트 종료 후 자동 갱신 여부 확인 |

특히 **RDS Multi-AZ를 비용 절감을 이유로 임의 Single-AZ 전환하거나
Destroy하지 않는다.**

------------------------------------------------------------------------

## 11. 타 팀 협업 프로세스 (접속 매뉴얼 제공 및 변경 요청)

**원칙**: 모든 AWS 리소스의 생성·삭제는 **인프라팀이 Terraform으로만
수행**합니다. 타 팀은 콘솔에 직접 접근하거나 리소스를 직접 조작하지
않습니다.

### 11.1 리소스 제공 방식

인프라팀이 리소스를 프로비저닝한 뒤, 각 팀에 **접속 매뉴얼**을
제공합니다. 매뉴얼에는 다음 내용이 포함됩니다.

-   서비스별 엔드포인트/도메인
-   배포 방법 (예: ECR Push, ArgoCD Sync 트리거 방법)
-   로그/모니터링 대시보드 접근 경로 (Grafana 등)
-   환경변수/Secret 전달 방식 (K8s Secret 등)
-   문의 채널

### 11.2 변경·삭제·재시작·스펙 상향 요청 프로세스

타 팀에서 리소스 관련 이슈(스펙 부족, 재시작 필요, 설정 변경 등)가
생기면 아래 흐름을 따릅니다.

승인보류/추가 논의타 팀: 이슈 발생요청 문서 작성인프라팀
접수검토비용·영향도 확인 Terraform으로 반영요청 팀과 협의요청 팀에 완료
공지

### 11.3 요청 문서 템플릿 (안)

| 항목 | 작성 내용 |
| --- | --- |
| 요청 팀 |  |
| 요청일 |  |
| 대상 리소스 | 예: BE Pod, AI 노드 등 |
| 요청 유형 | 스펙 상향 / 재시작 / 설정 변경 / 삭제 / 신규 생성 |
| 사유 |  |
| 희망 스펙·설정값 | 예: cpu 0.5→1, mem 1Gi→2Gi |
| 긴급도 | 낮음 / 보통 / 높음 |
| 영향 범위(예상) | 다운타임 발생 여부 등 |

### 11.4 처리 원칙

-   인프라팀은 요청 접수 시 \*\*비용 영향(예산 대비 증감)\*\*을 우선
    확인 후 반영
-   반영은 반드시 **Terraform 코드 변경 + PR**로 처리하며, 콘솔에서 직접
    반영하지 않음
-   긴급 대응(예: 서비스 다운)이 발생해 즉시 조치한 경우에도, 사후에
    반드시 Terraform 코드에 반영해 실제 상태와 코드가 어긋나지 않도록 함
-   처리 결과는 요청 팀에 공지

> **리소스 변경 및 추가 작업 요청 / 비용 알림을 위한 Discord 채널을 공통
> 운영 채널로 사용한다.**
>
> 타 파트는 다음 요청을 해당 채널에 전달한다.
>
> -   리소스 스펙 변경
> -   신규 리소스 추가
> -   운영시간 연장
> -   주말/공휴일 인프라 사용
> -   기타 인프라 변경 요청
>
> 인프라팀은 요청을 확인한 후 비용 및 서비스 영향을 검토하여
> Terraform/Helm에 반영한다.

------------------------------------------------------------------------

## 12. 모니터링 & 알림

AWS Budgets 알림 임계값은 **50 / 80 / 100%** 3단계로 설정한다
(`terraform/modules/budget-alert`, 월 한도 \$552, Discord Webhook 통지).

| 사용률 | 금액 | 대응 |
| --- | --- | --- |
| **50%** | \$276 | 정상 사용 여부 및 비용 증가 서비스 확인 |
| **80%** | \$441.60 | 신규 리소스/스펙 상향 재검토, ElastiCache/OpenSearch EKS 자체 호스팅 전환 검토 및 실행 여부 결정 (8장 권장 운영 규칙 참고) |
| **100%** | \$552 | 예산 초과 대응 --- 자체 호스팅 전환 즉시 실행, 신규 리소스 생성 중단 |

임계값 사이 구간(예: 60%, 90%)은 별도 알림이 발송되지 않으므로 아래 주간
점검으로 확인한다. 임계값을 조정할 경우 본 표와
`budget_notification_thresholds` 변수를 함께 수정한다.

-   AWS Cost Explorer **주 1회 이상 확인**
-   스크럼에서 현재 비용 간단 공유
-   급격한 비용 증가 발생 시 Discord 비용 채널에 공유
-   예상 비용 증가가 발생한 서비스는 원인과 조치사항 기록

------------------------------------------------------------------------

## 13. 미확정 / 확인 필요 항목 (Action Items)

| 항목 | 현재 상태 | 확인 필요 대상 |
| --- | --- | --- |
| Redis 실제 활용 기능(Session/Cache/PubSub) | Amazon ElastiCache 사용은 확정, 구체적으로 어떤 기능에 쓰이는지는 미확정 | BE팀 |
| AI팀 외부 API 사용 여부·비용 | AI팀 요구사항 문서상 "외부 API 미사용" 명시, 최신 상황 재확인 필요 | AI팀 |
| OpenSearch 색인 대상·연동 방식 | Amazon OpenSearch Service 사용은 확정, 실제 색인 데이터 및 BE/FE 연동 방식은 미확정 | BE/FE팀 |
| BE/AI Pod Resource Spec | CPU Worker 기반으로 변경됨. `requests/limits`는 `[확정 필요]`이며, 확정 후 `t3.large × N` 수용 가능 여부 검증 필요 | BE/AI팀 / 인프라팀 |
| 도메인 결제 주체·카드 | 미정 | 도메인 네임 활용 여부부터 타 파트와 논의할 것. 결제는 상우님이 인프라 포함 일괄 결제 |
| 접속 매뉴얼 템플릿 | 미작성 | 필요 시 작성 |

------------------------------------------------------------------------

## 14. 체크리스트 (9/7 작업 시작 전)

-   [x] AWS Budget Alert 설정 (50/80/100%)
-   [x] 비용 태그 표준 전체 개발팀에 공지
-   [ ] NAT Instance(t3a.micro) Terraform 모듈화, Source/Dest Check
    비활성화 확인
-   [ ] Tailscale 계정 생성 및 AWS·KT Cloud 양쪽 Subnet Router 설정
-   [x] 가비아 도메인 구매 및 결제 담당자 지정
-   [ ] 주간 비용 점검 담당자 지정
-   [x] 타 팀 변경 요청 접수 채널 확정
-   [ ] 접속 매뉴얼 템플릿 작성 및 각 팀 전달 방식 정리