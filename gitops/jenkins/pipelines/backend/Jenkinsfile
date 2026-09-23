// Jenkinsfile (backend)
//
// gitops/jenkins/pipelines/Jenkinsfile.template을 기반으로
// backend 서비스에 맞게 만든 파일입니다.
// 리뷰 후 최종적으로는 MoongCheap-backend 레포 최상단에
// 이 파일 이름 그대로(Jenkinsfile) 복사해서 사용합니다.
//
// NOTE: Dependency Scan / Secret Scan / Container Image Scan 스테이지는
// 원래 PR #28에서 추가됐었는데, 이후 Jenkinsfile.template 구조로
// 리팩터링하면서 누락됐던 걸 여기서 다시 복구함.

pipeline {
    agent none

    options {
        timeout(time: 90, unit: 'MINUTES')
        disableConcurrentBuilds(abortPrevious: true)
    }

    environment {
        SERVICE_NAME    = 'backend'
        ECR_REPO        = 'moongcheap/backend'
        ECR_REGISTRY    = '840851421204.dkr.ecr.ap-northeast-2.amazonaws.com'
        AWS_REGION      = 'ap-northeast-2'
        GITOPS_REPO_URL = 'https://github.com/V-MoongCheap/MoongCheap-Cloud.git'
        DOCKERFILE_PATH = 'docker/Dockerfile'
    }

    stages {
        stage('Build') {
            agent {
                kubernetes {
                    inheritFrom 'java-builder'
                }
            }

            steps {
                checkout scm

                script {
                    if (env.BRANCH_NAME == 'main') {
                        env.ENVIRONMENT = 'prod'
                        env.BASE_BRANCH = 'main'
                    } else if (env.BRANCH_NAME == 'develop') {
                        env.ENVIRONMENT = 'develop'
                        env.BASE_BRANCH = 'develop'
                    } else {
                        error "지원하지 않는 배포 브랜치입니다: ${env.BRANCH_NAME}"
                    }

                    env.GIT_SHORT_SHA = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG = "${env.ENVIRONMENT}-${env.GIT_SHORT_SHA}"

                    env.SPRING_PROFILE =
                        (env.ENVIRONMENT == 'prod') ? 'prod' : 'dev'

                    echo "Git Commit SHA: ${env.GIT_SHORT_SHA}"
                    echo "Image Tag: ${env.IMAGE_TAG}"
                    echo "Spring Profile: ${env.SPRING_PROFILE}"
                }

                container('builder') {
                    sh '''
                        set -eu

                        chmod +x gradlew
                        ./gradlew clean build -x test --no-daemon
                    '''
                }

                stash name: 'build-output',
                      includes: '**',
                      excludes: '.git/**'
            }
        }

        stage('Test') {
            agent {
                kubernetes {
                    inheritFrom 'java-builder'
                }
            }

            steps {
                unstash 'build-output'

                container('builder') {
                    sh '''
                        set -eu

                        chmod +x gradlew
                        ./gradlew test --no-daemon
                    '''
                }
            }
        }

        stage('Dependency Scan') {
            agent {
                kubernetes {
                    inheritFrom 'java-builder'
                }
            }

            steps {
                unstash 'build-output'

                container('builder') {
                    sh '''
                        set -eu

                        TRIVY_VERSION=0.56.2

                        curl -fSL \
                          -o trivy.tar.gz \
                          "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

                        tar -xzf trivy.tar.gz trivy
                        chmod +x trivy

                        ./trivy fs \
                          --severity HIGH,CRITICAL \
                          --exit-code 1 \
                          .
                    '''
                }
            }
        }

        stage('Secret Scan') {
            agent {
                kubernetes {
                    inheritFrom 'java-builder'
                }
            }

            steps {
                unstash 'build-output'

                container('builder') {
                    sh '''
                        set -eu

                        GITLEAKS_VERSION=8.21.2

                        curl -fSL \
                          -o gitleaks.tar.gz \
                          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"

                        tar -xzf gitleaks.tar.gz gitleaks
                        chmod +x gitleaks

                        ./gitleaks dir . \
                          --exit-code 1 \
                          --redact
                    '''
                }
            }
        }

        stage('Build, Scan & Push Image') {
            agent {
                kubernetes {
                    inheritFrom 'java-builder'
                }
            }

            steps {
                unstash 'build-output'

                // ECR에 Push하지 않고 이미지 TAR 생성
                container('kaniko') {
                    sh '''
                        set -eu

                        /kaniko/executor \
                          --context="$PWD" \
                          --dockerfile="$PWD/$DOCKERFILE_PATH" \
                          --build-arg "SPRING_PROFILES_ACTIVE=$SPRING_PROFILE" \
                          --destination="$ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG" \
                          --tar-path="$PWD/image.tar" \
                          --no-push \
                          --no-push-cache
                    '''
                }

                // Trivy 검사 → ECR 기존 태그 확인 → Push
                container('security') {
                    sh '''
                        set -eu

                        export DEBIAN_FRONTEND=noninteractive

                        apt-get update -qq

                        apt-get install -y -qq \
                          --no-install-recommends \
                          ca-certificates curl skopeo

                        python -m pip install \
                          --no-cache-dir \
                          --quiet \
                          awscli

                        TRIVY_VERSION=0.56.2

                        curl -fSL \
                          -o trivy.tar.gz \
                          "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

                        tar -xzf trivy.tar.gz trivy
                        chmod +x trivy

                        # HIGH / CRITICAL 발견 시 중단
                        ./trivy image \
                          --input image.tar \
                          --severity HIGH,CRITICAL \
                          --exit-code 1

                        # --------------------------------------------------
                        # ECR에 동일한 이미지 태그가 존재하는지 확인
                        # --------------------------------------------------

                        echo "ECR 이미지 확인: ${ECR_REPO}:${IMAGE_TAG}"

                        IMAGE_COUNT="$(aws ecr batch-get-image \
                          --region "$AWS_REGION" \
                          --repository-name "$ECR_REPO" \
                          --image-ids "imageTag=$IMAGE_TAG" \
                          --query 'length(images)' \
                          --output text)"


                        # --------------------------------------------------
                        # ECR 인증
                        # --------------------------------------------------

                        AUTH_DIR="$(mktemp -d)"
                        AUTH_FILE="$AUTH_DIR/auth.json"

                        trap 'rm -rf "$AUTH_DIR"' EXIT

                        aws ecr get-login-password \
                          --region "$AWS_REGION" |
                          skopeo login \
                            --authfile "$AUTH_FILE" \
                            --username AWS \
                            --password-stdin \
                            "$ECR_REGISTRY"


                        # --------------------------------------------------
                        # 기존 이미지 존재 여부에 따라 처리
                        # --------------------------------------------------

                        if [ "$IMAGE_COUNT" = '1' ]; then

                            echo "ECR에 동일한 태그가 존재합니다."
                            echo "기존 ECR 이미지를 검사합니다."

                            # 실제 ECR에 저장된 이미지를 TAR 파일로 다운로드
                            skopeo copy \
                              --authfile "$AUTH_FILE" \
                              "docker://$ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG" \
                              "docker-archive:$PWD/existing-image.tar"

                            # 기존 ECR 이미지의 HIGH / CRITICAL 취약점 검사
                            ./trivy image \
                              --input existing-image.tar \
                              --severity HIGH,CRITICAL \
                              --exit-code 1

                            echo "기존 ECR 이미지 보안 검사 통과"
                            echo "Push를 생략하고 GitOps 업데이트로 진행합니다."


                        elif [ "$IMAGE_COUNT" = '0' ]; then

                            echo "ECR에 동일한 태그가 없습니다."
                            echo "새로운 이미지를 Push합니다."

                            # 앞에서 Trivy 검사에 통과한 이미지 Push
                            skopeo copy \
                              --authfile "$AUTH_FILE" \
                              "docker-archive:$PWD/image.tar" \
                              "docker://$ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG"

                            echo "ECR Push 완료: $ECR_REPO:$IMAGE_TAG"


                        else

                            echo "예상하지 못한 ECR 이미지 조회 결과: $IMAGE_COUNT"
                            exit 1

                        fi
                    '''
                }
            }
        }

        stage('Update GitOps Repo (Image Tag)') {
            agent {
                kubernetes {
                    inheritFrom 'node-builder'
                }
            }

            steps {
                container('builder') {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'gitops-repo-push',
                            usernameVariable: 'GIT_USER',
                            passwordVariable: 'GIT_TOKEN'
                        )
                    ]) {
                        sh '''
                            set +x
                            set -eu

                            REPO_HOST="${GITOPS_REPO_URL#https://}"

                            BRANCH_NAME="ci/update-${SERVICE_NAME}-${IMAGE_TAG}-${BUILD_NUMBER}"

                            # ----------------------------------------
                            # GitHub 인증 설정
                            # ----------------------------------------

                            ASKPASS_FILE="$(mktemp)"

                            chmod 700 "$ASKPASS_FILE"

                            trap 'rm -f "$ASKPASS_FILE"' EXIT

                            printf '%s\\n' \
                              '#!/bin/sh' \
                              'case "$1" in' \
                              '  *Username*|*username*) printf "%s\\\\n" "$GIT_USER" ;;' \
                              '  *Password*|*password*) printf "%s\\\\n" "$GIT_TOKEN" ;;' \
                              '  *) exit 1 ;;' \
                              'esac' > "$ASKPASS_FILE"

                            export GIT_ASKPASS="$ASKPASS_FILE"
                            export GIT_TERMINAL_PROMPT=0

                            # ----------------------------------------
                            # GitOps Repository Clone
                            # ----------------------------------------

                            git -c credential.helper= clone \
                              "$GITOPS_REPO_URL" \
                              gitops-repo

                            cd gitops-repo

                            git -c credential.helper= fetch \
                              origin "$BASE_BRANCH"

                            git checkout -b \
                              "$BRANCH_NAME" \
                              "origin/$BASE_BRANCH"

                            # ----------------------------------------
                            # 이미지 태그 변경
                            # ----------------------------------------

                            OVERRIDE_FILE="gitops/values/overrides/${ENVIRONMENT}/${SERVICE_NAME}.yaml"

                            YQ_VERSION="v4.44.3"

                            curl -fSL \
                              "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
                              -o yq

                            chmod +x yq

                            ./yq -i \
                              '.image.tag = strenv(IMAGE_TAG)' \
                              "$OVERRIDE_FILE"

                            # ----------------------------------------
                            # Helm Validation
                            # ----------------------------------------

                            HELM_VERSION="v3.17.3"

                            curl -fSL \
                              "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
                              -o helm.tar.gz

                            tar -xzf helm.tar.gz linux-amd64/helm

                            HELM_BIN="$PWD/linux-amd64/helm"

                            CHART_DIR="gitops/charts/moongcheap-service"

                            BASE_VALUES="gitops/values/base.yaml"

                            ENV_VALUES="gitops/values/env/${ENVIRONMENT}.yaml"

                            SERVICE_VALUES="gitops/values/services/${SERVICE_NAME}.yaml"

                            # Helm Chart 검사
                            "$HELM_BIN" lint "$CHART_DIR" \
                              -f "$BASE_VALUES" \
                              -f "$ENV_VALUES" \
                              -f "$SERVICE_VALUES" \
                              -f "$OVERRIDE_FILE"

                            # Kubernetes Manifest 생성 검사
                            "$HELM_BIN" template \
                              "$SERVICE_NAME" \
                              "$CHART_DIR" \
                              --namespace "moongcheap-${ENVIRONMENT}" \
                              -f "$BASE_VALUES" \
                              -f "$ENV_VALUES" \
                              -f "$SERVICE_VALUES" \
                              -f "$OVERRIDE_FILE" \
                              > /dev/null

                            echo "Helm 검증 완료"

                            # ----------------------------------------
                            # 변경 사항 확인
                            # ----------------------------------------

                            if git diff --quiet -- "$OVERRIDE_FILE"; then

                                echo "이미지 태그가 이미 $IMAGE_TAG 입니다."
                                echo "GitOps PR 생성을 생략합니다."

                                exit 0

                            fi

                            # ----------------------------------------
                            # Git Commit / Push
                            # ----------------------------------------

                            git config user.name 'jenkins-ci'

                            git config user.email \
                              'jenkins-ci@moongcheap.local'

                            git add "$OVERRIDE_FILE"

                            git commit \
                              -m "ci(gitops): update ${SERVICE_NAME} image tag to ${IMAGE_TAG}"

                            git -c credential.helper= push \
                              origin "$BRANCH_NAME"

                            # ----------------------------------------
                            # GitHub PR 생성
                            # ----------------------------------------

                            GITOPS_API_REPO="${REPO_HOST#github.com/}"

                            GITOPS_API_REPO="${GITOPS_API_REPO%.git}"

                            PR_TITLE="ci(gitops): update ${SERVICE_NAME} image tag to ${IMAGE_TAG}"

                            PR_JSON="$(printf \
                              '{"title":"%s","head":"%s","base":"%s"}' \
                              "$PR_TITLE" \
                              "$BRANCH_NAME" \
                              "$BASE_BRANCH")"

                            curl --fail-with-body \
                              -sS \
                              -X POST \
                              -H "Authorization: Bearer ${GIT_TOKEN}" \
                              -H 'Accept: application/vnd.github+json' \
                              "https://api.github.com/repos/${GITOPS_API_REPO}/pulls" \
                              -d "$PR_JSON"
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                try {
                    withCredentials([
                        string(
                            credentialsId: 'discord-webhook-ci',
                            variable: 'DISCORD_WEBHOOK'
                        )
                    ]) {
                        discordSend(
                            webhookURL: env.DISCORD_WEBHOOK,
                            title: "Backend CI #${env.BUILD_NUMBER}",
                            description: "서비스: Backend / 결과: ${currentBuild.currentResult} / 브랜치: ${env.BRANCH_NAME ?: '확인 불가'} / 환경: ${env.ENVIRONMENT ?: '미설정'} / 태그: ${env.IMAGE_TAG ?: '미생성'}",
                            link: env.BUILD_URL,
                            result: currentBuild.currentResult,
                            footer: 'MoongCheap Backend CI (배포 완료 알림 아님)'
                        )
                    }
                } catch (Exception e) {
                    echo 'Discord CI 알림 전송 실패 — Jenkins Credentials와 Plugin 설정 확인'
                }
            }
        }

        success {
            echo "Backend CI 완료: ${ECR_REPO}:${IMAGE_TAG}. GitOps PR Merge 후 ArgoCD Sync 진행."
        }

        failure {
            echo 'Backend CI 실패 — Jenkins 로그에서 실패 Stage 확인 필요.'
        }
    }
}