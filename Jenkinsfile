/* Jenkinsfile - Pipeline SCM 配置修复 */
/* 方案：使用 GitHub App 凭证或 Personal Access Token 进行认证 */
/* 需要在 Jenkins 凭证管理中预先配置以下凭证之一：
 * 1. github-app-credentials (GitHub App 方式，推荐)
 * 2. github-pat-credentials (Personal Access Token)
 * 3. github-ssh-key (SSH 密钥方式)
 */

// ============================================================
// 方案一：使用 GitHub Personal Access Token (PAT) - 最常用
// 在 Jenkins 中创建 Username with password 凭证：
//   Username: 你的 GitHub 用户名
//   Password: 生成的 Personal Access Token (classic 或 fine-grained)
//   ID: github-pat-credentials
// ============================================================

pipeline {
    agent any
    
    options {
        // 增加重试次数和超时时间
        retry(3)
        timeout(time: 30, unit: 'MINUTES')
        // 禁用并发构建避免资源冲突
        disableConcurrentBuilds()
    }
    
    environment {
        // 设置 Git 使用凭证助手，避免交互式提示
        GIT_TERMINAL_PROMPT = '0'
        // 禁用 SSL 验证（仅用于内部测试环境，生产环境不建议）
        // GIT_SSL_NO_VERIFY = 'true'
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    // 使用 withCredentials 注入凭证，避免硬编码
                    // 需要先在 Jenkins 中配置名为 'github-pat-credentials' 的凭证
                    withCredentials([usernamePassword(
                        credentialsId: 'github-pat-credentials',
                        usernameVariable: 'GITHUB_USER',
                        passwordVariable: 'GITHUB_TOKEN'
                    )]) {
                        // 使用嵌入凭证的 URL 进行克隆
                        // 注意：这种方式在日志中可能会暴露 URL，建议使用 checkout scm 配合凭证 ID
                        sh '''
                            # 清理旧工作区避免冲突
                            git config --global --add safe.directory "$(pwd)" || true
                            
                            # 使用 token 认证方式
                            git clone --depth 1 "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/bobwei192-star/pipeline.git" . || \
                            git fetch --tags --force --progress "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/bobwei192-star/pipeline.git" +refs/heads/*:refs/remotes/origin/*
                        '''
                    }
                }
                
                // 或者使用更安全的 Jenkins 原生 checkout 方式（推荐）
                // 需要在 Jenkins 作业配置或 Jenkinsfile 中指定 credentialsId
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],  // 或 '*/master' 根据默认分支调整
                    extensions: [
                        [$class: 'CloneOption', depth: 1, noTags: false, shallow: true],
                        [$class: 'CleanBeforeCheckout'],
                        [$class: 'WipeWorkspace']
                    ],
                    userRemoteConfigs: [[
                        url: 'https://github.com/bobwei192-star/pipeline.git',
                        credentialsId: 'github-pat-credentials'  // 必须在 Jenkins 凭证中预先配置
                    ]]
                ])
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo 'Building ROCm on Ryzen Docker image...'
                // 原有的 Docker 构建步骤
                sh '''
                    # 检查 Docker 环境
                    command -v docker >/dev/null 2>&1 || { echo "Docker not found"; exit 1; }
                    docker info >/dev/null 2>&1 || { echo "Docker daemon not accessible"; exit 1; }
                    
                    # 构建命令（根据实际项目调整）
                    # docker build -t rocm-ryzen:latest .
                '''
            }
        }
    }
    
    post {
        failure {
            echo 'Build failed. Checking common issues...'
            script {
                // 失败时输出诊断信息
                sh '''
                    echo "=== Git 配置诊断 ==="
                    git config --list --show-origin 2>/dev/null || true
                    echo "=== 网络连通性测试 ==="
                    curl -I -s https://github.com 2>/dev/null | head -5 || true
                    echo "=== Jenkins 环境变量 ==="
                    env | grep -i git || true
                '''
            }
        }
        always {
            // 清理敏感信息
            sh '''
                git config --global --unset-all url."https://***:***@github.com/".insteadOf 2>/dev/null || true
            '''
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
    }
}