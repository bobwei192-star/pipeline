pipeline {
    agent any
    
    options {
        // 增加重试次数，避免因临时网络问题导致构建失败
        retry(3)
    }
    
    environment {
        // 使用环境变量或凭据来管理 Git 认证信息
        // 需要在 Jenkins 中配置 'github-pat-credentials' 凭据（类型：Username with password，密码填 PAT）
        GIT_URL = 'https://github.com/bobwei192-star/pipeline.git'
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    // 使用凭据进行代码拉取
                    // 注意：需要在 Jenkins 中预先配置凭据 ID
                    checkout scm: [
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],
                        extensions: [
                            [$class: 'CloneOption', timeout: 30]
                        ],
                        userRemoteConfigs: [[
                            url: env.GIT_URL,
                            credentialsId: 'github-pat-credentials'
                        ]]
                    ]
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    // 原有的 Docker 构建逻辑
                    echo 'Building ROCm on Ryzen Docker image...'
                    // 实际的构建命令需要根据原始 Jenkinsfile 补充
                }
            }
        }
    }
    
    post {
        failure {
            script {
                echo 'Build failed. Please check:'
                echo '1. Ensure Jenkins credential "github-pat-credentials" exists with GitHub Personal Access Token'
                echo '2. Verify the PAT has required scopes: repo, read:packages'
                echo '3. Check if the repository URL is accessible from Jenkins agent'
            }
        }
    }
}