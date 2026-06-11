pipeline {
    agent any
    
    options {
        // 添加重试配置，但主要修复是凭证配置
        retry(3)
    }
    
    environment {
        // 设置 Git 使用 HTTPS 时的凭证助手（可选，用于调试）
        GIT_TRACE = '1'
    }
    
    stages {
        stage('Checkout') {
            steps {
                // 使用 withCredentials 显式指定凭证
                // 注意：需要在 Jenkins 中预先配置好 ID 为 'github-token' 的凭证
                // 或者使用已有的凭证 ID
                script {
                    // 尝试使用多种方式检出代码
                    try {
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            extensions: [],
                            userRemoteConfigs: [[
                                url: 'https://github.com/bobwei192-star/pipeline.git',
                                credentialsId: 'github-pat-token'  // 请替换为实际的凭证 ID
                            ]]
                        ])
                    } catch (Exception e) {
                        echo "First checkout attempt failed: ${e.getMessage()}"
                        // 备用：尝试不带凭证（对于公开仓库）
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            extensions: [],
                            userRemoteConfigs: [[
                                url: 'https://github.com/bobwei192-star/pipeline.git'
                            ]]
                        ])
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo 'Building ROCm on Ryzen Docker image...'
                // 添加实际的 Docker 构建命令
                sh '''
                    # 检查 Docker 环境
                    docker --version || echo "Docker not available"
                    
                    # 构建镜像
                    # docker build -t rocm-ryzen:latest .
                '''
            }
        }
    }
    
    post {
        failure {
            echo 'Build failed. Please check Git credentials configuration.'
            echo 'Ensure a valid GitHub Personal Access Token is configured in Jenkins credentials.'
        }
    }
}