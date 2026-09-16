variable "project" {
  type        = string
  description = "프로젝트 이름"
  default     = "moongcheap"
}

variable "env" {
  type        = string
  description = "환경 구분 (develop/prod)"
}

variable "cluster_name" {
  type        = string
  description = "EKS 클러스터 이름 (modules/eks 출력값)"
}

variable "oidc_provider_arn" {
  type        = string
  description = "EKS OIDC Provider ARN (modules/eks 출력값, IRSA 신뢰 정책에서 사용)"
}

variable "oidc_issuer_url" {
  type        = string
  description = "EKS OIDC Issuer URL (modules/eks 출력값, IRSA 신뢰 정책 조건절에서 사용)"
}

# Karpenter가 만드는 EC2는 클러스터 SG를 자동으로 못 받아서 직접 태그해야 한다
# (be_ai SG/WAS Subnet은 modules/eks·vpc가 이미 태그하므로 여기선 이것만 받는다).
variable "cluster_security_group_id" {
  type        = string
  description = "EKS 클러스터 SG ID (modules/eks 출력값) — be_ai SG와 함께 Karpenter 노드에 붙여야 컨트롤 플레인 통신이 됨"
}

# Karpenter Helm Chart(GitOps에서 ArgoCD로 설치)가 이 이름/네임스페이스로 ServiceAccount를
# 만든다는 전제 하에 IRSA 신뢰 정책을 건다. GitOps 쪽 values와 반드시 일치해야 한다.
variable "karpenter_namespace" {
  type        = string
  description = "Karpenter 컨트롤러가 설치될 Kubernetes Namespace"
  default     = "kube-system"
}

variable "karpenter_service_account_name" {
  type        = string
  description = "Karpenter 컨트롤러 ServiceAccount 이름"
  default     = "karpenter"
}
