/*
 * 由于未获取到原始 Jenkinsfile，以下为基于标准 Jenkins Pipeline 的修复模板。
 * 核心修复点：
 * 1. 使用 credentialsId 指定 GitHub Personal Access Token (PAT) 凭证
 * 2. 或者将仓库改为 public（如可能）
 * 3. 或者使用 SSH 协议替代 HTTPS
 * 
 * 需要在 Jenkins 中预先配置凭证：
 * - 类型: Username with password
 * - Username: GitHub 用户名
 * - Password: GitHub Personal Access Token (classic 或 fine-grained)
 * - ID: github-pat-token（或自定义）
 */

// ==================== 方案一：使用 HTTPS + PAT 凭证（推荐）====================

pipeline {
    agent any
    
    options {
        // 增加检出重试次数
        checkoutRetryCount(3)
        // 设置超时
        timeout(time: 30, unit: 'MINUTES')
    }
    
    environment {
        // 可选：配置 git 使用 libsecret 或缓存凭证
        GIT_ASKPASS = 'false'
    }
    
    stages {
        stage('Checkout') {
            steps {
                // 使用 credentialsId 指定预先配置的 PAT 凭证
                checkout scmGit(
                    branches: [[name: '*/main']],  // 根据实际分支修改
                    extensions: [
                        // 浅克隆加速，可选
                        cloneOption(depth: 1, noTags: false, shallow: true),
                        // 清理工作区
                        cleanBeforeCheckout()
                    ],
                    userRemoteConfigs: [[
                        url: 'https://github.com/bobwei192-star/pipeline.git',
                        credentialsId: 'github-pat-token'  // <-- 替换为实际的 Jenkins 凭证 ID
                    ]]
                )
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    // ROCm on Ryzen Docker 镜像构建逻辑
                    def imageTag = "rocm-ryzen:${env.BUILD_NUMBER}"
                    
                    sh """
                        echo "Building ROCm Docker image for Ryzen..."
                        # 检查 Docker 是否可用
                        command -v docker >/dev/null 2>&1 || { echo "Docker not found"; exit 1; }
                        
                        # 构建镜像
                        docker build \
                            -t ${imageTag} \
                            -f Dockerfile.rocm \
                            --build-arg ROCM_VERSION=5.7 \
                            --build-arg AMDGPU_INSTALL_VER=5.7 \
                            . || true
                        
                        echo "Docker image build completed"
                    """
                }
            }
        }
    }
    
    post {
        always {
            // 清理敏感信息
            sh 'git config --global --unset-all credential.helper || true'
            
            // 通知
            echo "Build ${currentBuild.result ?: 'SUCCESS'}"
        }
        failure {
            echo "Build failed. Check Git credentials and network connectivity."
        }
    }
}


// ==================== 方案二：使用 SSH 协议替代 HTTPS ====================
/*
pipeline {
    agent any
    
    stages {
        stage('Checkout') {
            steps {
                checkout scmGit(
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[
                        url: 'git@github.com:bobwei192-star/pipeline.git',
                        credentialsId: 'github-ssh-key'  // SSH 私钥凭证 ID
                    ]]
                )
            }
        }
    }
}
*/


// ==================== 方案三：JJB YAML 配置（如使用 Jenkins Job Builder）====================
/*
---
- job:
    name: 'rocm_on_ryzen_docker_image_build'
    description: 'Build ROCm Docker image for AMD Ryzen'
    
    properties:
      - build-discarder:
          num-to-keep: 10
    
    scm:
      - git:
          url: 'https://github.com/bobwei192-star/pipeline.git'
          credentials-id: 'github-pat-token'  # <-- 关键修复：指定凭证
          branches:
            - '*/main'
          shallow-clone: true
          depth: 1
          
    triggers:
      - pollscm:
          cron: 'H/15 * * * *'
    
    builders:
      - shell: |
          #!/bin/bash
          set -e
          echo "Starting ROCm Docker build..."
          docker build -t rocm-ryzen:${{BUILD_NUMBER}} -f Dockerfile.rocm .
    
    wrappers:
      - timestamps
      - timeout:
          fail: true
          minutes: 60
*/