pipeline {
    agent any
    
    options {
        // 增加 SCM 检出重试次数
        checkoutRetryCount(3)
    }
    
    environment {
        // 使用 GitHub Personal Access Token 进行认证
        // 需要在 Jenkins Credentials 中配置名为 'github-pat' 的 Secret Text 类型凭据
        GIT_URL = 'https://github.com/bobwei192-star/pipeline.git'
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    // 使用凭据进行 Git 检出
                    // 方案1: 使用用户名+密码/PAT（推荐）
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],  // 根据实际分支修改，如 master, develop 等
                        extensions: [
                            [$class: 'CloneOption', depth: 1, noTags: false, shallow: true],
                            [$class: 'CleanBeforeCheckout']
                        ],
                        userRemoteConfigs: [[
                            url: env.GIT_URL,
                            credentialsId: 'github-pat'  // Jenkins 中配置的凭据 ID
                        ]]
                    ])
                }
            }
        }
        
        stage('Build ROCm Docker Image') {
            steps {
                echo 'Building ROCm on Ryzen Docker image...'
                // 实际的 Docker 构建步骤
                // sh 'docker build -t rocm-ryzen:latest .'
            }
        }
    }
    
    post {
        failure {
            echo 'Build failed. Please check Git credentials and network connectivity.'
        }
        always {
            // 清理工作区（可选）
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
    }
}