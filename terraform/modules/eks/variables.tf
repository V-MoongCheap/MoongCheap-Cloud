variable "project" {
  type        = string
  description = "프로젝트 이름"
  default     = "moongcheap"
}

variable "env" {
  type        = string
  description = "환경 구분 (develop/prod)"
}

# 현재 운영 중인 클러스터가 1.36이라(2026-09-17 describe-cluster 확인) 같은 값으로 고정.
# 올릴 때는 Karpenter chart·Add-on 호환표를 먼저 확인하고 이 값만 바꿔 apply한다(다운그레이드 불가).
variable "cluster_version" {
  type        = string
  description = "EKS Kubernetes minor 버전 (예: \"1.36\"). 패치 버전은 AWS가 관리"
  default     = "1.36"
}

variable "cluster_role_arn" {
  type        = string
  description = "EKS 클러스터(컨트롤 플레인)용 IAM Role ARN (modules/iam 출력값)"
}

variable "subnet_ids" {
  type        = list(string)
  description = "클러스터 컨트롤 플레인이 사용할 Subnet ID 목록 (WEB+WAS Private Subnet 합집합, modules/vpc 출력값)"
}

variable "web_subnet_ids" {
  type        = list(string)
  description = "FE Worker Node Group을 배치할 WEB Private Subnet ID 목록 (아키텍처 설계서_V2 4.2)"
}

variable "was_subnet_ids" {
  type        = list(string)
  description = "System Worker Node Group을 배치할 WAS Private Subnet ID 목록 (DEC-1)"
}

variable "vpc_id" {
  type        = string
  description = "FE/BE·AI 전용 Security Group을 생성할 VPC ID (modules/vpc 출력값)"
}

variable "node_role_arn" {
  type        = string
  description = "EKS Worker Node용 IAM Role ARN (modules/iam 출력값)"
}

# D-30: 호출부의 module 단위 depends_on = [module.iam]을 대체하는 입력.
# 이 두 목록을 locals에서 참조하기만 해서(값은 안 씀) "iam 정책 attachment → EKS" 순서를
# 암묵 의존으로 만든다. module depends_on은 iam 모듈에 아무 변경(태그 한 줄)이 생겨도
# 이 모듈의 data source 읽기를 apply 시점까지 미뤄 account_id가 unknown → Access Entry
# 5명 전원 replace를 일으켰다(2026-09-21, 현황 문서 D-30 / 트러블슈팅 2026-09-17-04와 같은 메커니즘).
variable "cluster_role_policy_attachment_ids" {
  type        = list(string)
  description = "클러스터 Role 정책 attachment ID 목록 (modules/iam 출력값, 순서 의존 전용)"
  default     = []
}

variable "node_role_policy_attachment_ids" {
  type        = list(string)
  description = "Node Role 정책 attachment ID 목록 (modules/iam 출력값, 순서 의존 전용)"
  default     = []
}

# 아키텍처 설계서_V2 4.2: FE는 t3.small 고정 Managed Node Group을 유지한다.
# BE·AI(Backend/API/AI CPU/Jenkins/ArgoCD/Observability 통합)는 modules/karpenter가
# 대체하므로 여기엔 인스턴스 타입 변수가 없다.
variable "fe_instance_type" {
  type        = string
  description = "FE Worker Node Group 인스턴스 타입"
  default     = "t3.small"
}

# Karpenter 등 태그로 SG를 찾는 외부 컨트롤러용 확장 포인트. be_ai SG에만 적용한다
# (fe SG는 외부 컨트롤러가 찾을 이유가 없다).
variable "be_ai_security_group_tags" {
  type        = map(string)
  description = "be_ai Security Group에 추가할 태그"
  default     = {}
}

variable "cluster_admin_usernames" {
  type        = list(string)
  description = "클러스터 admin 권한을 받을 IAM 사용자 이름 목록"
  default     = ["v-infra-hs", "v-infra-jh", "v-infra-jw", "v-infra-sw", "v-infra-ys"]
}

# true(기본값)면 클러스터를 실제로 만든 사람에게 AWS가 자동으로 admin 권한을 준다.
# 이 경우 그 사람 몫을 access.tf가 cluster_admin_usernames에서 빼야 충돌이 안 난다 —
# 근데 그 "제외 대상"은 매번 apply하는 사람이 아니라 "최초 생성자" 단 한 명으로
# 고정해야 한다(D-17 정정, 실제로 다른 팀원이 apply할 때 본인 access entry가 삭제되는
# 걸 라이브로 재현함). 신규 클러스터(prod 등)는 false로 두면 이 특수 케이스 자체가
# 없어져서 팀원 전원을 예외 없이 동일하게 관리할 수 있다.
variable "bootstrap_cluster_creator_admin_permissions" {
  type        = bool
  description = "클러스터 생성자에게 AWS가 자동으로 admin 권한을 줄지 여부. 새로 만드는 클러스터는 false 권장(D-17)"
  default     = true
}

# bootstrap_cluster_creator_admin_permissions = true인 환경에서만 의미가 있다.
# "지금 apply하는 사람"이 아니라 "이 클러스터를 최초로 만든 사람"으로 고정해야
# 한다. develop은 v-infra-jh가 최초 생성자였으나(AWS 자동 생성, Terraform 태그
# 없음으로 확인), 이 변수를 고치기 전의 버그 있는 코드가 그 자동 생성 항목
# 자체를 지워버렸다(2026-09-18 실측). AWS의 자동 부여는 클러스터 생성 시점에
# 딱 한 번만 발생해 다시 살아나지 않으므로, 더 이상 보호할 대상이 없어 기본값을
# 빈 문자열로 둔다 — 이러면 team_admins가 아무도 빼지 않아 jh도 나머지처럼
# Terraform이 정상적으로 관리한다. 앞으로 클러스터를 재생성해서 실제로 자동
# admin을 받는 사람이 생기면, 그때 그 사람 이름으로 이 값을 다시 채울 것.
variable "cluster_creator_username" {
  type        = string
  description = "이 클러스터를 최초로 apply해서 AWS 자동 admin을 받은 IAM 사용자 이름 (없으면 빈 문자열)"
  default     = ""
}

# 아키텍처 설계서_V2 4.2: FE Desired=2(Open 시). Runbook 7.1의 Close는 MGMT 서버가
# EKS API로 desired를 0으로 내리는 방식이라 min_size가 0이어야 하고, 그 뒤 apply가
# desired를 되돌리지 않도록 node_groups.tf에서 desired_size를 ignore_changes 처리한다.
variable "fe_desired_size" {
  type        = number
  description = "FE Worker Node Group desired size (최초 생성 시 값. 이후 Open/Close 스크립트가 바꾸며 Terraform은 무시)"
  default     = 2
}

variable "fe_min_size" {
  type        = number
  description = "FE Worker Node Group min size (Close 때 desired=0이 가능하려면 0이어야 함)"
  default     = 0
}

variable "eso_namespace" {
  type        = string
  description = "External Secrets Operator가 설치될 Kubernetes Namespace (naming_convention_V2.md 5.1: infra)"
  default     = "infra"
}

variable "eso_service_account_name" {
  type        = string
  description = "External Secrets Operator ServiceAccount 이름 — Helm Chart values의 serviceAccount.name과 반드시 일치해야 함"
  default     = "external-secrets"
}

# ── Workload IRSA (C-5) ──────────────────────────────────────────────────
# Jenkins Agent(kaniko)가 ECR에 push할 때 쓰는 SA. gitops/platform/jenkins/config.yaml의
# namespace와 values.yaml의 serviceAccount.name과 반드시 일치해야 한다.
variable "jenkins_namespace" {
  type        = string
  description = "Jenkins가 설치된 Kubernetes Namespace"
  default     = "infra"
}

variable "jenkins_service_account_name" {
  type        = string
  description = "Jenkins Controller/Agent ServiceAccount 이름 (gitops values의 serviceAccount.name)"
  default     = "jenkins-sa"
}

# BE Pod가 S3 Object 버킷에 접근할 때 쓰는 SA (naming_convention_V2.md 5.4: be-sa).
# 서비스 Namespace는 moongcheap-{env}라 env로부터 계산한다.
variable "be_service_account_name" {
  type        = string
  description = "Backend ServiceAccount 이름 (공통 Chart serviceAccount.name)"
  default     = "be-sa"
}

variable "be_s3_bucket_arn" {
  type        = string
  description = "BE가 읽고 쓸 S3 Object 버킷 ARN (modules/s3 출력값). 빈 문자열이면 BE Role을 만들지 않는다"
  default     = ""
}

variable "fe_max_size" {
  type        = number
  description = "FE Worker Node Group max size"
  default     = 2
}

# DEC-1: BE·AI가 Karpenter(동적 노드)로 바뀌면서 ArgoCD·Karpenter Controller·Jenkins
# Controller처럼 항상 떠있어야 하는 시스템 워크로드가 붙을 고정 자리가 없어졌다.
# FE에 얹으면(대안 (b)) 사용자 트래픽과 클러스터 운영 워크로드가 자원을 두고 경합하므로,
# 별도 System Node Group을 신설한다(대안 (a), 채택). t3.medium 1대(allocatable ~3.4GiB)로는
# ArgoCD(~6 Pod)+Karpenter Controller(2 Pod, 권장 1Gi×2)+Jenkins Controller만으로도
# 부족해 2대로 시작한다(추정 — 실측 후 조정).
variable "system_instance_type" {
  type        = string
  description = "System Worker Node Group 인스턴스 타입 (ArgoCD/Karpenter Controller/Jenkins Controller)"
  default     = "t3.medium"
}

variable "system_desired_size" {
  type        = number
  description = "System Worker Node Group desired size"
  default     = 2
}

variable "system_min_size" {
  type        = number
  description = "System Worker Node Group min size (Close 때 desired=0이 가능하려면 0이어야 함 — Runbook 7.1)"
  default     = 0
}

variable "system_max_size" {
  type        = number
  description = "System Worker Node Group max size"
  default     = 2
}
