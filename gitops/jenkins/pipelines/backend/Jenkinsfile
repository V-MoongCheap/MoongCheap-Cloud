// Jenkinsfile (backend)

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

        // GitOps PR 결과 전달용
        GITOPS_PR_NUMBER     = ''
        GITOPS_PR_URL        = ''
        GITOPS_PR_STATUS     = ''
        GITOPS_BRANCH_STATUS = ''
        GITOPS_PR_CREATED    = 'false'
    }

    stages {

        // ============================================================
        // Build
        // ============================================================

        stage('Build') {
            agent {
                kubernetes {
                    inheritFrom 'java-builder'
                }
            }

            steps {
                checkout scm

                script {

                    // --------------------------------------------------
                    // Branch → Environment
                    // --------------------------------------------------

                    if (env.BRANCH_NAME == 'main') {
                        env.ENVIRONMENT = 'prod'
                        env.BASE_BRANCH = 'main'

                    } else if (env.BRANCH_NAME == 'develop') {
                        env.ENVIRONMENT = 'develop'
                        env.BASE_BRANCH = 'develop'

                    } else {
                        error "지원하지 않는 배포 브랜치입니다: ${env.BRANCH_NAME}"
                    }


                    // --------------------------------------------------
                    // Git 정보
                    // --------------------------------------------------

                    env.GIT_SHORT_SHA = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    env.GIT_FULL_SHA = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true
                    ).trim()

                    env.GIT_AUTHOR = sh(
                        script: 'git log -1 --pretty=format:%an',
                        returnStdout: true
                    ).trim()

                    env.GIT_COMMIT_URL =
                        "https://github.com/V-MoongCheap/MoongCheap-backend/commit/${env.GIT_FULL_SHA}"


                    // --------------------------------------------------
                    // Image / Spring Profile
                    // --------------------------------------------------

                    env.IMAGE_TAG =
                        "${env.ENVIRONMENT}-${env.GIT_SHORT_SHA}"

                    env.SPRING_PROFILE =
                        (env.ENVIRONMENT == 'prod') ? 'prod' : 'dev'


                    echo "Git Commit SHA: ${env.GIT_SHORT_SHA}"
                    echo "Image Tag: ${env.IMAGE_TAG}"
                    echo "Spring Profile: ${env.SPRING_PROFILE}"


                    // --------------------------------------------------
                    // Discord - CI 시작
                    // --------------------------------------------------

                    try {
                        withCredentials([
                            string(
                                credentialsId: 'discord-webhook-ci',
                                variable: 'DISCORD_WEBHOOK'
                            )
                        ]) {
                            discordSend(
                                webhookURL: env.DISCORD_WEBHOOK,
                                title: "🚀 Backend CI 시작",
                                description: """
**Branch**  ${env.BRANCH_NAME}
**Build**   #${env.BUILD_NUMBER}

🔗 [Jenkins Build](${env.BUILD_URL})
""".stripIndent()
                            )
                        }
                    } catch (Exception e) {
                        echo "Discord CI 시작 알림 전송 실패: ${e.getClass().getSimpleName()}"
                    }
                }


                // --------------------------------------------------
                // Gradle Build
                // --------------------------------------------------

                container('builder') {
                    sh '''
                        set -eu

                        chmod +x gradlew

                        ./gradlew clean build \
                          -x test \
                          --no-daemon
                    '''
                }


                stash name: 'build-output',
                      includes: '**',
                      excludes: '.git/**'
            }
        }


        // ============================================================
        // Test
        // ============================================================

        stage('Test') {
            agent {
                kubernetes {
                    inheritFrom 'java-builder'

                    yaml '''
                      apiVersion: v1
                      kind: Pod

                      spec:
                        containers:

                          - name: dind
                            image: docker:27.5.1-dind

                            command:
                              - dockerd

                            args:
                              - --host=unix:///var/run/docker.sock
                              - --host=tcp://127.0.0.1:2375
                              - --tls=false

                            securityContext:
                              privileged: true

                            resources:
                              requests:
                                cpu: "200m"
                                memory: "512Mi"

                            volumeMounts:
                              - name: docker-data
                                mountPath: /var/lib/docker

                        volumes:
                          - name: docker-data
                            emptyDir: {}
                    '''
                }
            }

            steps {

                unstash 'build-output'

                container('builder') {

                    withEnv([
                        'DOCKER_HOST=tcp://127.0.0.1:2375',
                        'TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock'
                    ]) {

                        sh '''
                            set -eu

                            export TESTCONTAINERS_HOST_OVERRIDE="$(hostname -i | awk '{print $1}')"

                            echo "Docker Engine 연결 확인"
                            echo "Testcontainers Host: $TESTCONTAINERS_HOST_OVERRIDE"

                            chmod +x gradlew

                            ./gradlew test \
                              -PskipContainerTests \
                              --no-daemon
                        '''
                    }
                }
            }
        }


        // ============================================================
        // Dependency Scan
        // ============================================================

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

                        TRIVY_VERSION=0.74.0

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


        // ============================================================
        // Secret Scan
        // ============================================================

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


        // ============================================================
        // Container Build / Scan / ECR Push
        // ============================================================

        stage('Build, Scan & Push Image') {
            agent {
                kubernetes {
                    inheritFrom 'java-builder'
                }
            }

            steps {

                unstash 'build-output'


                // --------------------------------------------------
                // Kaniko
                // --------------------------------------------------

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


                // --------------------------------------------------
                // Trivy → ECR
                // --------------------------------------------------

                container('security') {

                    sh '''
                        set -eu

                        export DEBIAN_FRONTEND=noninteractive

                        apt-get update -qq

                        apt-get install -y -qq \
                          --no-install-recommends \
                          ca-certificates \
                          curl \
                          skopeo

                        python -m pip install \
                          --no-cache-dir \
                          --quiet \
                          awscli


                        # ------------------------------------------
                        # Trivy 설치
                        # ------------------------------------------

                        TRIVY_VERSION=0.74.0

                        curl -fSL \
                          -o trivy.tar.gz \
                          "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

                        tar -xzf trivy.tar.gz trivy

                        chmod +x trivy


                        # ------------------------------------------
                        # Container Image Scan
                        # ------------------------------------------

                        ./trivy image \
                          --input image.tar \
                          --severity HIGH,CRITICAL \
                          --exit-code 0


                        # ------------------------------------------
                        # ECR 이미지 존재 확인
                        # ------------------------------------------

                        echo "ECR 이미지 확인: ${ECR_REPO}:${IMAGE_TAG}"

                        IMAGE_COUNT="$(aws ecr batch-get-image \
                          --region "$AWS_REGION" \
                          --repository-name "$ECR_REPO" \
                          --image-ids "imageTag=$IMAGE_TAG" \
                          --query 'length(images)' \
                          --output text)"


                        # ------------------------------------------
                        # ECR 인증
                        # ------------------------------------------

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


                        # ------------------------------------------
                        # Push
                        # ------------------------------------------

                        if [ "$IMAGE_COUNT" = '1' ]; then

                            echo "ECR에 동일한 태그가 존재합니다."
                            echo "기존 ECR 이미지를 검사합니다."

                            skopeo copy \
                              --authfile "$AUTH_FILE" \
                              "docker://$ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG" \
                              "docker-archive:$PWD/existing-image.tar"

                            ./trivy image \
                              --input existing-image.tar \
                              --severity HIGH,CRITICAL \
                              --exit-code 0

                            echo "기존 ECR 이미지 보안 검사 완료"
                            echo "Push를 생략하고 GitOps 업데이트로 진행합니다."


                        elif [ "$IMAGE_COUNT" = '0' ]; then

                            echo "ECR에 동일한 태그가 없습니다."
                            echo "새로운 이미지를 Push합니다."

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


        // ============================================================
        // GitOps
        // ============================================================

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

                            rm -f \
                              gitops-pr-number.txt \
                              gitops-pr-url.txt \
                              gitops-pr-status.txt \
                              gitops-branch-status.txt \
                              gitops-pr-created.txt

                            REPO_HOST="${GITOPS_REPO_URL#https://}"

                            BRANCH_NAME="ci/update-${SERVICE_NAME}-${IMAGE_TAG}-${BUILD_NUMBER}"


                            # ========================================
                            # GitHub 인증
                            # ========================================

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


                            # ========================================
                            # GitOps Repository
                            # ========================================

                            git -c credential.helper= clone \
                              "$GITOPS_REPO_URL" \
                              gitops-repo

                            cd gitops-repo

                            git -c credential.helper= fetch \
                              origin "$BASE_BRANCH"

                            git checkout -b \
                              "$BRANCH_NAME" \
                              "origin/$BASE_BRANCH"


                            # ========================================
                            # Image Tag 변경
                            # ========================================

                            OVERRIDE_FILE="gitops/values/overrides/${ENVIRONMENT}/${SERVICE_NAME}.yaml"

                            YQ_VERSION="v4.44.3"

                            curl -fSL \
                              "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
                              -o yq

                            chmod +x yq

                            ./yq -i \
                              '.image.tag = strenv(IMAGE_TAG)' \
                              "$OVERRIDE_FILE"


                            # ========================================
                            # Helm Validation
                            # ========================================

                            HELM_VERSION="v3.17.3"

                            curl -fSL \
                              "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
                              -o helm.tar.gz

                            tar -xzf \
                              helm.tar.gz \
                              linux-amd64/helm

                            HELM_BIN="$PWD/linux-amd64/helm"

                            CHART_DIR="gitops/charts/moongcheap-service"

                            BASE_VALUES="gitops/values/base.yaml"

                            ENV_VALUES="gitops/values/env/${ENVIRONMENT}.yaml"

                            SERVICE_VALUES="gitops/values/services/${SERVICE_NAME}.yaml"


                            "$HELM_BIN" lint "$CHART_DIR" \
                              -f "$BASE_VALUES" \
                              -f "$ENV_VALUES" \
                              -f "$SERVICE_VALUES" \
                              -f "$OVERRIDE_FILE"


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


                            # ========================================
                            # 변경사항 확인
                            # ========================================

                            if git diff --quiet -- "$OVERRIDE_FILE"; then

                                echo "이미지 태그가 이미 $IMAGE_TAG 입니다."
                                echo "GitOps PR 생성을 생략합니다."

                                exit 0

                            fi


                            # ========================================
                            # Git Commit / Push
                            # ========================================

                            git config user.name \
                              'jenkins-ci'

                            git config user.email \
                              'jenkins-ci@moongcheap.local'

                            git add \
                              "$OVERRIDE_FILE"

                            git commit \
                              -m "ci(gitops): update ${SERVICE_NAME} image tag to ${IMAGE_TAG}"

                            git -c credential.helper= push \
                              origin "$BRANCH_NAME"


                            # ========================================
                            # GitHub PR 생성
                            # ========================================

                            GITOPS_API_REPO="${REPO_HOST#github.com/}"
                            GITOPS_API_REPO="${GITOPS_API_REPO%.git}"

                            PR_TITLE="ci(gitops): update ${SERVICE_NAME} image tag to ${IMAGE_TAG}"

                            PR_JSON="$(printf \
                              '{"title":"%s","head":"%s","base":"%s"}' \
                              "$PR_TITLE" \
                              "$BRANCH_NAME" \
                              "$BASE_BRANCH")"

                            PR_RESPONSE="$(curl --fail-with-body \
                              -sS \
                              -X POST \
                              -H "Authorization: Bearer ${GIT_TOKEN}" \
                              -H 'Accept: application/vnd.github+json' \
                              "https://api.github.com/repos/${GITOPS_API_REPO}/pulls" \
                              -d "$PR_JSON")"


                            PR_NUMBER="$(printf '%s' "$PR_RESPONSE" | node -pe \
                              'JSON.parse(require("fs").readFileSync(0, "utf8")).number')"

                            PR_NODE_ID="$(printf '%s' "$PR_RESPONSE" | node -pe \
                              'JSON.parse(require("fs").readFileSync(0, "utf8")).node_id')"

                            echo "GitOps PR 생성 완료: #${PR_NUMBER}"


                            # Jenkins post 블록으로 전달
                            echo "$PR_NUMBER" \
                              > ../gitops-pr-number.txt

                            echo "https://github.com/V-MoongCheap/MoongCheap-Cloud/pull/${PR_NUMBER}" \
                              > ../gitops-pr-url.txt

                            echo "true" \
                              > ../gitops-pr-created.txt


                            # ========================================
                            # Auto Merge
                            # develop / main 공통
                            # ========================================

                            echo "GitOps PR Auto-merge 활성화: #${PR_NUMBER} → ${BASE_BRANCH}"

                            GRAPHQL_QUERY="$(printf \
                              '{"query":"mutation { enablePullRequestAutoMerge(input: {pullRequestId: \\"%s\\", mergeMethod: SQUASH}) { pullRequest { number autoMergeRequest { enabledAt } } } }"}' \
                              "$PR_NODE_ID")"

                            MERGE_RESPONSE="$(curl --fail-with-body \
                              -sS \
                              -X POST \
                              -H "Authorization: Bearer ${GIT_TOKEN}" \
                              -H 'Accept: application/vnd.github+json' \
                              "https://api.github.com/graphql" \
                              -d "$GRAPHQL_QUERY")"


                            printf '%s' "$MERGE_RESPONSE" | node -e '
                              const fs = require("fs");

                              const result =
                                JSON.parse(
                                  fs.readFileSync(0, "utf8")
                                );

                              if (
                                result.errors ||
                                !result.data
                                  ?.enablePullRequestAutoMerge
                                  ?.pullRequest
                                  ?.autoMergeRequest
                              ) {
                                console.error(
                                  JSON.stringify(result)
                                );

                                process.exit(1);
                              }
                            '

                            echo "Auto-merge 활성화 완료: PR #${PR_NUMBER}"


                            # ========================================
                            # Merge 완료 대기
                            # ========================================

                            echo "GitOps PR Merge 완료 대기: #${PR_NUMBER}"

                            MAX_RETRIES=30
                            RETRY_INTERVAL=10
                            RETRY_COUNT=0
                            MERGED="false"

                            while true; do

                                PR_STATUS="$(curl --fail-with-body \
                                  -sS \
                                  -H "Authorization: Bearer ${GIT_TOKEN}" \
                                  -H 'Accept: application/vnd.github+json' \
                                  "https://api.github.com/repos/${GITOPS_API_REPO}/pulls/${PR_NUMBER}")"


                                MERGED="$(printf '%s' "$PR_STATUS" | node -pe \
                                  'JSON.parse(require("fs").readFileSync(0, "utf8")).merged')"


                                if [ "$MERGED" = "true" ]; then

                                    echo "GitOps PR Merge 완료: #${PR_NUMBER}"

                                    break

                                fi


                                RETRY_COUNT=$((RETRY_COUNT + 1))


                                if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then

                                    echo "GitOps PR Merge 대기 시간 초과"

                                    echo "임시 브랜치는 삭제하지 않습니다."

                                    break

                                fi


                                echo "아직 Merge되지 않았습니다. ${RETRY_INTERVAL}초 후 재확인..."

                                sleep "$RETRY_INTERVAL"

                            done


                            # ========================================
                            # Merge 후 임시 Branch 삭제
                            # ========================================

                            if [ "$MERGED" = "true" ]; then
                              if git ls-remote \
                                  --exit-code \
                                  --heads origin "$BRANCH_NAME" \
                                  >/dev/null 2>&1
                              then
                                  git -c credential.helper= push \
                                    origin \
                                    --delete "$BRANCH_NAME"

                                  echo "GitOps 임시 브랜치 삭제 완료: ${BRANCH_NAME}"
                              else
                                  echo "GitOps 임시 브랜치가 이미 삭제되어 있습니다: ${BRANCH_NAME}"
                              fi

                                echo "Merged" \
                                  > ../gitops-pr-status.txt

                                echo "Deleted" \
                                  > ../gitops-branch-status.txt

                            else

                                echo "Pending" \
                                  > ../gitops-pr-status.txt

                                echo "Retained" \
                                  > ../gitops-branch-status.txt

                            fi
                        '''


                        // --------------------------------------------
                        // Shell 결과 → Jenkins Environment
                        // --------------------------------------------

                        script {

                            if (fileExists('gitops-pr-number.txt')) {

                                env.GITOPS_PR_NUMBER =
                                    readFile(
                                        'gitops-pr-number.txt'
                                    ).trim()
                            }


                            if (fileExists('gitops-pr-url.txt')) {

                                env.GITOPS_PR_URL =
                                    readFile(
                                        'gitops-pr-url.txt'
                                    ).trim()
                            }


                            if (fileExists('gitops-pr-status.txt')) {

                                env.GITOPS_PR_STATUS =
                                    readFile(
                                        'gitops-pr-status.txt'
                                    ).trim()
                            }


                            if (fileExists('gitops-branch-status.txt')) {

                                env.GITOPS_BRANCH_STATUS =
                                    readFile(
                                        'gitops-branch-status.txt'
                                    ).trim()
                            }


                            if (fileExists('gitops-pr-created.txt')) {

                                env.GITOPS_PR_CREATED =
                                    readFile(
                                        'gitops-pr-created.txt'
                                    ).trim()
                            }
                        }
                    }
                }
            }
        }
    }


    // ================================================================
    // Result Notification
    // ================================================================

    post {

        // ------------------------------------------------------------
        // SUCCESS
        // ------------------------------------------------------------

        success {

            script {

                def gitopsInfo = ""


                if (env.GITOPS_PR_CREATED == 'true') {

                    gitopsInfo = """
                    **GitOps PR**    #${env.GITOPS_PR_NUMBER ?: '-'} ${env.GITOPS_PR_STATUS ?: '-'}
                    **Temp Branch**  ${env.GITOPS_BRANCH_STATUS ?: '-'}

                    🔗 [GitOps PR](${env.GITOPS_PR_URL})
                    """

                                    } else {

                                        gitopsInfo = """
                    **GitOps PR**    Skipped
                    """
                }


                try {

                    withCredentials([
                        string(
                            credentialsId: 'discord-webhook-ci',
                            variable: 'DISCORD_WEBHOOK'
                        )
                    ]) {

                        discordSend(
                            webhookURL: env.DISCORD_WEBHOOK,
                            title: "✅ Backend CI 성공",
                            description: """
                            **Environment**  ${env.ENVIRONMENT ?: '-'}
                            **Branch**       ${env.BRANCH_NAME ?: '-'}
                            **Triggered**    ${env.GIT_AUTHOR ?: '-'}
                            **Commit**       ${env.GIT_SHORT_SHA ?: '-'}
                            **Image**        ${env.IMAGE_TAG ?: '-'}
                            **Build**        #${env.BUILD_NUMBER}

                            ${gitopsInfo}
                            🔗 [GitHub Commit](${env.GIT_COMMIT_URL})
                            🔗 [Jenkins Build](${env.BUILD_URL})
                            """.stripIndent(),
                            result: 'SUCCESS'
                        )
                    }

                } catch (Exception e) {

                    echo "Discord CI 알림 전송 실패: ${e.getClass().getSimpleName()}"

                }
            }
        }


        // ------------------------------------------------------------
        // FAILURE
        // ------------------------------------------------------------

        failure {

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
                            title: "❌ Backend CI 실패",
                            description: """
                            **Environment**  ${env.ENVIRONMENT ?: '-'}
                            **Branch**       ${env.BRANCH_NAME ?: '-'}
                            **Triggered**    ${env.GIT_AUTHOR ?: '-'}
                            **Commit**       ${env.GIT_SHORT_SHA ?: '-'}
                            **Build**        #${env.BUILD_NUMBER}

                            🔗 [GitHub Commit](${env.GIT_COMMIT_URL ?: 'https://github.com/V-MoongCheap/MoongCheap-backend'})
                            🔗 [Jenkins Build](${env.BUILD_URL})
                            """.stripIndent(),
                            result: 'FAILURE'
                        )
                    }

                } catch (Exception e) {

                    echo "Discord CI 알림 전송 실패: ${e.getClass().getSimpleName()}"

                }
            }
        }


        // ------------------------------------------------------------
        // ABORTED
        // ------------------------------------------------------------

        aborted {

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
                            title: "⚠️ Backend CI 중단",
                            description: """
                            **Branch**       ${env.BRANCH_NAME ?: '-'}
                            **Triggered**    ${env.GIT_AUTHOR ?: '-'}
                            **Build**        #${env.BUILD_NUMBER}

                            🔗 [Jenkins Build](${env.BUILD_URL})
                            """.stripIndent(),
                            result: 'ABORTED'
                        )
                    }

                } catch (Exception e) {

                    echo "Discord CI 알림 전송 실패: ${e.getClass().getSimpleName()}"

                }
            }
        }
    }
}