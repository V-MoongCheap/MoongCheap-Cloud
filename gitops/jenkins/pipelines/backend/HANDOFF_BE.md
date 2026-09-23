# MoongCheap Backend — Jenkins CI/CD 핸드오프

- **전달 대상:** Backend 팀
- **서비스 저장소:** `V-MoongCheap/MoongCheap-backend`
- **Jenkinsfile 적용 위치:** 서비스 저장소 최상단 `Jenkinsfile`
- **Cloud 관리 위치:** `MoongCheap-Cloud/gitops/jenkins/pipelines/backend/Jenkinsfile`
- **Cloud 기준:** `develop` 커밋 `de3aa45` (2026-09-23 확인)
- **현재 상태:** Jenkinsfile 작성 및 코드 검토 완료 / Jenkins·EKS 실제 통합 빌드 **미검증**

## 1. Backend 팀에 전달하는 파일

| 파일 | 목적 |
| --- | --- |
| `Jenkinsfile` | Backend 레포에서 실행할 Jenkins Pipeline |
| `HANDOFF.md` | 적용 방법, 팀 확인 사항, 인수인계 기준 |

서비스 레포 최상단에 `Jenkinsfile`을 반영하고 Cloud 담당자에게 PR 주소를 전달한다. **Jenkins Job이 Backend 레포를 Source로 바라보아야 한다.** `checkout scm`은 Jenkins Job에 연결된 저장소를 Checkout하므로, Cloud의 관리본을 수정하는 것만으로 Backend 코드 빌드가 연결되는 것은 아니다.

## 2. CI → GitOps → CD 흐름

```text
Backend develop / main Push
  → Jenkins: Backend 레포 Checkout
  → Gradle Build / Gradle Test
  → Trivy Dependency Scan
  → Gitleaks Secret Scan (현재 소스 디렉터리; Git 전체 이력 검사 아님)
  → Kaniko: Backend 이미지 TAR 생성 (아직 ECR Push 안 함)
  → Trivy Image Scan: HIGH / CRITICAL 발견 시 CI 중단
  → ECR 동일 이미지 태그 확인
      ├─ 없음 → 신규 이미지 Push
      └─ 있음 → ECR 기존 이미지 다운로드·재검사 후 재사용
  → Cloud GitOps backend 이미지 태그 수정 + Helm lint/template
  → Cloud 레포 대상 브랜치에 GitOps PR 생성 (태그 변경 없으면 생략)
  → Discord: Backend CI 결과 알림
  → 담당자: GitOps PR 리뷰 / Merge
  → ArgoCD: Sync / Health 확인 → 서비스 실행 확인
```

**CI 성공 알림 = 배포 완료가 아님.** GitOps PR Merge 이후 ArgoCD 배포까지 따로 확인한다.

## 3. 브랜치·환경·경로

| 서비스 브랜치 | Spring Profile | GitOps PR 대상 | 배포 Namespace | 이미지 태그 |
| --- | --- | --- | --- | --- |
| `develop` | `dev` | Cloud `develop` | `moongcheap-develop` | `develop-<7자리 Git SHA>` |
| `main` | `prod` | Cloud `main` | `moongcheap-prod` | `prod-<7자리 Git SHA>` |

- ECR 이미지: `840851421204.dkr.ecr.ap-northeast-2.amazonaws.com/moongcheap/backend:<태그>`
- Dockerfile: 서비스 레포 `docker/Dockerfile` (루트 `Dockerfile` 아님)
- GitOps 업데이트: `gitops/values/overrides/<환경>/backend.yaml` 안의 `image.tag`
- 그 밖의 브랜치는 현재 Jenkinsfile에서 배포 Pipeline을 중단한다. Feature/PR 체크는 기존 서비스 CI와 구분한다.

## 4. Backend 팀이 확인하고 회신할 항목

- [ ] `Jenkinsfile`을 `MoongCheap-backend` 레포 최상단에 적용할 수 있는지 확인
- [ ] `docker/Dockerfile` 경로 유지 및 이미지 빌드 정상 동작 여부 확인
- [ ] JDK 25 / Gradle Wrapper / `./gradlew clean build -x test --no-daemon` 실행 여부 확인
- [ ] `./gradlew test --no-daemon` 실행 시 DB·Redis·OAuth 등 외부 의존성 및 필요한 테스트 설정 전달
- [ ] `develop → dev`, `main → prod` Spring Profile 매핑 확인
- [ ] `application-dev`·`application-prod` 및 Kubernetes 환경변수/Secret 주입 요구사항 전달
- [ ] 배포 후 Backend Health·DB 연결·API 정상 응답 기준 공유
- [ ] Trivy/Gitleaks 결과로 코드·의존성 수정이 필요하면 Backend 담당자가 원인을 확인하고 조치

### 빌드 중복 참고

현재 Jenkinsfile의 Gradle Build 뒤에 `docker/Dockerfile`에서도 `./gradlew clean bootJar --no-daemon`을 실행한다. 첫 통합 빌드에서는 현행 구조를 검증하고, 빌드 시간 최적화는 이후 Cloud·Backend 공동 검토 사항으로 둔다.

### 기존 이미지 태그 재사용 참고

동일 SHA 태그가 ECR에 이미 있으면 기존 이미지를 내려받아 Trivy 재검사한 뒤 재사용한다. 단, **방금 새로 만든 이미지와 기존 이미지의 Digest가 동일한지 확인하는 구현은 아니다.** Docker 베이스 이미지·의존성 변경에 따라 같은 소스 커밋이라도 산출물이 달라질 수 있으므로 재실행 결과를 함께 확인한다.


> 현재 코드는 정적 검토 단계이며, Kaniko → TAR → Skopeo → ECR 및 Jenkins Kubernetes Agent의 실제 동작은 첫 통합 빌드에서 확인해야 한다.
