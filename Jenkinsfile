pipeline {
    agent any
    
    options {
        // 设置 Git 相关选项
        skipDefaultCheckout(false)
    }
    
    environment {
        // 使用环境变量存储凭证 ID，便于管理和修改
        GITHUB_CREDENTIALS_ID = 'github-pat-credentials'
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    // 使用 credentialsId 进行认证，支持 HTTPS with PAT
                    checkout scmGit(
                        branches: scm.branches,
                        extensions: scm.extensions + [cleanBeforeCheckout()],
                        userRemoteConfigs: [[
                            url: 'https://github.com/bobwei192-star/pipeline.git',
                            credentialsId: env.GITHUB_CREDENTIALS_ID
                        ]]
                    )
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo 'Building ROCm on Ryzen Docker image...'
                // 原有的 Docker 构建步骤
            }
        }
    }
    
    post {
        always {
            echo 'Pipeline completed'
        }
        failure {
            echo 'Pipeline failed - check credentials configuration'
        }
    }
}