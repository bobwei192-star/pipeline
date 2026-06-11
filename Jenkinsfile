pipeline {
    agent any
    
    environment {
        // 使用 Jenkins 凭据 ID，需要在 Jenkins 中配置对应的凭据
        GIT_CREDENTIALS_ID = 'github-pat-credentials'
    }
    
    options {
        // 设置 Git 检出选项
        skipDefaultCheckout(false)
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    // 使用凭据检出代码
                    checkout scmGit(
                        branches: scm.branches,
                        extensions: [],
                        userRemoteConfigs: [[
                            url: 'https://github.com/bobwei192-star/pipeline.git',
                            credentialsId: env.GIT_CREDENTIALS_ID
                        ]]
                    )
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    // 构建 ROCm on Ryzen Docker 镜像
                    sh '''
                        echo "Building ROCm on Ryzen Docker image..."
                        # Docker 构建命令
                        docker build -t rocm-ryzen:latest .
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                // 清理工作区
                cleanWs()
            }
        }
        failure {
            script {
                echo "Build failed. Please check Git credentials configuration."
            }
        }
    }
}