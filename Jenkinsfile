pipeline {
    agent any
    
    // 配置 Git 凭据 - 使用 Jenkins 凭据 ID
    // 需要在 Jenkins 中预先配置凭据：
    // 1. 进入 Jenkins 管理页面 -> Manage Jenkins -> Manage Credentials
    // 2. 添加凭据：Username with password 类型
    //    - Username: GitHub 用户名
    //    - Password: GitHub Personal Access Token (classic 或 fine-grained)
    //    - ID: github-pat-token (或自定义)
    // 3. 确保该凭据有权限访问 bobwei192-star/pipeline 仓库
    
    options {
        // 设置 Git 检出选项
        checkoutToSubdirectory('source')
        // 禁用自动检出，使用自定义检出步骤
        skipDefaultCheckout(true)
    }
    
    environment {
        // 可选：设置 Git 相关环境变量
        GIT_SSL_NO_VERIFY = 'false'
    }
    
    stages {
        stage('Checkout') {
            steps {
                // 使用凭据进行 Git 检出
                // 请将 'github-pat-token' 替换为实际的 Jenkins 凭据 ID
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],
                    extensions: [
                        [$class: 'CloneOption', depth: 1, noTags: false, shallow: true, timeout: 30],
                        [$class: 'CleanBeforeCheckout']
                    ],
                    userRemoteConfigs: [[
                        url: 'https://github.com/bobwei192-star/pipeline.git',
                        credentialsId: 'github-pat-token'
                    ]]
                ])
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    // 原有的 Docker 构建步骤
                    echo 'Building ROCm on Ryzen Docker image...'
                }
            }
        }
    }
    
    post {
        failure {
            echo 'Build failed. Please verify GitHub credentials are configured correctly.'
            echo 'Ensure the Personal Access Token has repo scope permissions.'
        }
    }
}