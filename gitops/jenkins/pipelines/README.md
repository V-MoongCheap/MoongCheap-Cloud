# Jenkins CI/CD 파이프라인 구조

- **기준일:** 2026-09-28
- **기준 브랜치:** `feat/gitops` (backend/frontend 최신 패턴 기준), `develop` (그 외 공통 내용)
- **현재 상태:** 정적 코드 리뷰 단계 / Jenkins·EKS 실제 통합 빌드 미검증

이 문서는 `gitops/jenkins/pipelines/` 아래 각 서비스 Jenkinsfile이 공통으로 따르는 패턴과,
그 패턴이 왜 이렇게 설계됐는지를 설명합니다. 새 서비스 Jenkinsfile을 추가하거나
기존 파일을 수정할 때 기준으로 삼는 문서입니다.

## 1. 대상 서비스 및 현재 상태

| 서비스 | 경로 | 상태 |
| --- | --- | --- |
| Backend | `backend/Jenkinsfile` | 최신 패턴 적용 (`feat/gitops` 기준) |
| Frontend | `frontend/Jenkinsfile` | 최신 패턴 적용 (`feat/gitops` 기준) |
| AI (seller-analysis) | `ai/Jenkinsfile` | **구버전** — 아래 3번 항목 전에 만든 초기 패턴, Dependency/Secret Scan 등 미적용 |
| AI (awarding / a-labeling / demand-clustering) | 미생성 | 파트별 Job 구성 확정 후 추가 예정 (같은 ECR 레포, COMPONENT로 태그 구분) |

`Jenkinsfile.template`은 실제 배포되는 파일이 아니라 새 서비스 만들 때 참고하는 뼈대입니다.

## 2. 공통 파이프라인 흐름

- Build
- Test
- Dependency Scan (Trivy, 소스 파일시스템 스캔)
- Secret Scan (Gitleaks, 소스 디렉터리 스캔)
- Build, Scan & Push Image
    1. Kaniko로 이미지를 로컬 TAR로만 빌드 (--no-push)
    2. security 컨테이너에서 Trivy로 TAR 이미지 스캔 (HIGH/CRITICAL 발견 시 중단)
    3. ECR에 동일 태그 이미지가 있는지 확인
       - 있으면: 기존 이미지 재검사만 하고 재사용, push 생략
       - 없으면: Skopeo로 TAR를 ECR에 push
- Update GitOps Repo (Image Tag)
    1. GitOps 레포 클론 (GIT_ASKPASS 방식 인증)
    2. yq로 이미지 태그 갱신
    3. Helm lint / template로 차트 유효성 검증
    4. 변경사항 있으면 커밋 → 새 브랜치 push → GitHub PR 생성
    5. 변경사항 없으면(태그 동일) PR 생성 생략
- Discord 알림 (성공/실패, GitOps PR 링크 포함)

**왜 이 순서인가:**
- 이미지를 곧바로 ECR에 push하지 않고 TAR로 먼저 만든 뒤 스캔하는 이유는, 취약점이 있는 이미지가 레지스트리에 아예 올라가지 않도록 막기 위함입니다.
- ECR에 같은 태그가 있으면 재사용하는 이유는, 소스 변경 없이 같은 커밋으로 재빌드할 때 불필요한 중복 이미지를 만들지 않기 위함입니다. (단, Base 이미지/의존성이 바뀌면 같은 소스 커밋이라도 결과물이 달라질 수 있어 재검사는 항상 수행합니다.)
- "CI 성공 알림"과 "배포 완료"는 다릅니다. CI는 GitOps PR을 만드는 데까지고, 실제 배포는 그 PR이 머지되고 ArgoCD가 Sync 된 뒤에 이루어집니다.

## 3. 공통 환경변수 규칙

| 변수 | 의미 | 예시 |
| --- | --- | --- |
| `SERVICE_NAME` | 서비스 식별자 | `backend`, `frontend` |
| `ECR_REPO` | ECR 레포 경로 | `moongcheap/backend` |
| `ECR_REGISTRY` | ECR 레지스트리 주소 | `840851421204.dkr.ecr.ap-northeast-2.amazonaws.com` |
| `DOCKERFILE_PATH` | 서비스 레포 기준 Dockerfile 경로 | `docker/Dockerfile` (backend), `Dockerfile` (frontend) |
| `GITOPS_REPO_URL` | GitOps(Cloud) 레포 주소 | `https://github.com/V-MoongCheap/MoongCheap-Cloud.git` |
| `IMAGE_TAG` | 이미지 태그 형식 | `<환경>-<7자리 Git SHA>` (예: `develop-a1b2c3d`) |

## 4. 브랜치 → 환경 매핑

| 서비스 브랜치 | 환경 | GitOps PR 대상 | 배포 Namespace |
| --- | --- | --- | --- |
| `develop` | `dev` | Cloud `develop` | `moongcheap-develop` |
| `main` | `prod` | Cloud `main` | `moongcheap-prod` |

그 외 브랜치(feature/PR 등)는 배포 파이프라인을 타지 않습니다.

## 5. Jenkins Pod 템플릿

`gitops/platform/jenkins/values.yaml`에 정의되어 있으며, 아래 라벨로 `inheritFrom` 해서 사용합니다.

| 템플릿 | 대상 서비스 | 컨테이너 | 비고 |
| --- | --- | --- | --- |
| `java-builder` | Backend | builder, kaniko, security | Dependency/Secret Scan은 `builder`, 이미지 스캔/Push는 `security` |
| `node-builder` | Frontend, GitOps 업데이트 공통 | builder, kaniko, security | 위와 동일 |
| `python-builder` | AI (예정) | builder, kaniko | **security 컨테이너 없음 — AI Jenkinsfile을 최신 패턴으로 맞추려면 여기에 security 컨테이너 추가 필요 (values.yaml 수정 + Jenkins Helm upgrade 필요)** |

## 6. 필요한 Jenkins Credential

| Credential ID | 종류 | 용도 |
| --- | --- | --- |
| `discord-webhook-ci` | Secret text | CI 결과 디스코드 알림 |
| `gitops-repo-push` | Username/Password | GitOps 레포 clone/push, GitHub PR 생성용 토큰 |

새 서비스를 추가해도 이 두 Credential은 그대로 재사용하면 되고, 별도로 새로 만들 필요는 없습니다.

## 7. 알려진 미해결 사항

- Frontend `DEV_API_URL`이 아직 실제 develop 환경 주소로 확정되지 않음 (Frontend 팀 확인 필요)
- Backend `Test` 스테이지에 Docker-in-Docker(Testcontainers) 지원이 추가되었고, 해당 컨테이너가 `privileged: true`로 설정되어 있음 — 클러스터 보안 정책상 문제없는지 확인 필요
- AI 서비스(seller-analysis)는 아직 구버전 패턴 — Dependency/Secret Scan, TAR 기반 스캔, Helm Validation 미적용
- AI 나머지 3개 파트(awarding, a-labeling, demand-clustering) Jenkinsfile 미생성 — 파트별 Job 구성 확정 후 추가 예정
- 전체 파이프라인의 실제 Jenkins/EKS 통합 빌드는 아직 검증되지 않음 (정적 코드 리뷰 단계)
