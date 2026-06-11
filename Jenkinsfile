pipeline {
    agent any
    
    options {
        // 设置 Git 相关选项
        checkoutToSubdirectory('source')
    }
    
    environment {
        // 使用环境变量或凭据 ID 引用
        GIT_URL = 'https://github.com/bobwei192-star/pipeline.git'
    }
    
    stages {
        stage('Checkout') {
            steps {
                // 使用凭据进行 Git 检出
                // 注意：需要在 Jenkins 中配置名为 'github-pat' 的凭据
                git(
                    url: '${GIT_URL}',
                    branch: 'main',
                    credentialsId: 'github-pat'
                )
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    // 构建 ROCm on Ryzen Docker 镜像
                    sh '''
                        docker build -t rocm-ryzen:latest .
                    '''
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
    }
}