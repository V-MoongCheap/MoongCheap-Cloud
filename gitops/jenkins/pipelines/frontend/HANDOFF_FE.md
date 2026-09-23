# MoongCheap Frontend — Jenkins CI/CD 핸드오프

- **전달 대상:** Frontend 팀
- **서비스 저장소:** `V-MoongCheap/MoongCheap-frontend`
- **Jenkinsfile 적용 위치:** 서비스 저장소 최상단 `Jenkinsfile`
- **Cloud 관리 위치:** `MoongCheap-Cloud/gitops/jenkins/pipelines/frontend/Jenkinsfile`
- **기준일:** 2026-09-23
- **현재 상태:** Jenkinsfile 작성 및 코드 검토 완료 / Jenkins·EKS 실제 통합 빌드 **미검증**

## 1. Frontend 팀에 전달하는 파일

| 파일 | 목적 |
| --- | --- |
| `Jenkinsfile` | Frontend 레포에서 실행할 Jenkins Pipeline |
| `HANDOFF.md` | 적용 방법, 팀 확인 사항, 인수인계 기준 |

서비스 레포 최상단에 `Jenkinsfile`을 반영하고 Cloud 담당자에게 PR 주소를 전달한다. Cloud의 관리본과 서비스 레포의 실행본이 달라지면 어느 버전이 적용됐는지 함께 공유한다. **Jenkins Job이 Frontend 레포를 Source로 바라보아야 한다.** `checkout scm`은 Jenkins Job이 연결한 레포를 Checkout한다. Cloud에 파일만 올린 것으로 Frontend 소스 빌드가 연결되는 것은 아니다.

## 2. CI → GitOps → CD 흐름

```text
Frontend develop / main Push
  → Jenkins: Frontend 레포 Checkout
  → npm ci + npm run build
  → ESLint / Type Check / Prettier 검사
  → Trivy Dependency Scan
  → Gitleaks Secret Scan (현재 소스 디렉터리; Git 전체 이력 검사 아님)
  → Kaniko: Next.js 이미지 TAR 생성 (아직 ECR Push 안 함)
  → Trivy Image Scan: HIGH / CRITICAL 발견 시 CI 중단
  → ECR 동일 이미지 태그 확인
      ├─ 없음 → 신규 이미지 Push
      └─ 있음 → ECR 기존 이미지 다운로드·재검사 후 재사용
  → Cloud GitOps frontend 이미지 태그 수정 + Helm lint/template
  → Cloud 레포 대상 브랜치에 GitOps PR 생성 (태그 변경 없으면 생략)
  → Discord: Frontend CI 결과 알림
  → 담당자: GitOps PR 리뷰 / Merge
  → ArgoCD: Sync / Health 확인 → 서비스 실행 확인
```

**CI 성공 알림 = 배포 완료가 아님.** GitOps PR Merge 이후 ArgoCD 배포까지 따로 확인한다.

## 3. 브랜치·환경·경로

| 서비스 브랜치 | GitOps PR 대상 | 배포 Namespace | 이미지 태그 |
| --- | --- | --- | --- |
| `develop` | Cloud `develop` | `moongcheap-develop` | `develop-<7자리 Git SHA>` |
| `main` | Cloud `main` | `moongcheap-prod` | `prod-<7자리 Git SHA>` |

- ECR 이미지: `840851421204.dkr.ecr.ap-northeast-2.amazonaws.com/moongcheap/frontend:<태그>`
- Dockerfile: 서비스 레포 **루트** `Dockerfile`
- GitOps 업데이트: `gitops/values/overrides/<환경>/frontend.yaml` 안의 `image.tag`
- 그 밖의 브랜치는 현재 Jenkinsfile에서 배포 Pipeline을 중단한다. Feature/PR 체크는 기존 GitHub Actions와 구분한다.

## 4. Frontend 팀이 확인하고 회신할 항목

- [ ] `Jenkinsfile`을 `MoongCheap-frontend` 레포 최상단에 적용할 수 있는지 확인
- [ ] 기존 루트 `Dockerfile` 및 Next.js `output: 'standalone'` 사용 유지 여부 확인
- [ ] Node.js 20 및 `package-lock.json` 기준 `npm ci` 정상 실행 여부 확인
- [ ] `npm run build`, `npm run lint`, `npm run typecheck`, `npm run format:check` 통과 여부 확인
- [ ] **develop API URL 확정**: 현재 Jenkinsfile `DEV_API_URL='https://api.moongcheap.shop'`은 기존 Frontend 설정을 옮긴 것으로 실제 develop 주소인지 확인 필요
- [ ] 브라우저→Backend 통신, OAuth 리다이렉트, 쿠키/CORS 관련 실제 환경 확인
- [ ] 기존 GitHub Actions CI와 Jenkins CI의 실행 범위·필수 상태 검사(브랜치 보호) 중복 여부 팀 간 정리
- [ ] Trivy/Gitleaks 결과로 코드·의존성 수정이 필요하면 Frontend 담당자가 원인을 확인하고 조치

### 빌드 환경변수 안내

`NEXT_PUBLIC_API_BASE_URL`은 **Next.js Docker 이미지 빌드 시점**에 들어간다. 개발·운영 URL이 다르면 해당 환경에 맞춰 새 이미지를 빌드해야 하며, 배포 후 Kubernetes 환경변수만 바꿔서는 이미 생성된 클라이언트 코드의 주소가 바뀌지 않는다.


> 현재 코드는 정적 검토 단계이며, Kaniko → TAR → Skopeo → ECR 및 Jenkins Kubernetes Agent의 실제 동작은 첫 통합 빌드에서 확인해야 한다.
