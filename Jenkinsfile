pipeline {
    agent any
    
    options {
        // 设置 Git 检出行为，使用更稳定的配置
        checkoutToSubdirectory('source')
    }
    
    environment {
        // 可选：如果使用 PAT 作为环境变量，可以通过这种方式传递
        // GIT_TOKEN = credentials('github-pat-token')
    }
    
    stages {
        stage('Checkout') {
            steps {
                // 使用 credentialsId 指定 Jenkins 中配置的凭据
                // 需要在 Jenkins 中预先创建凭据：
                // 1. 进入 Jenkins -> Manage Jenkins -> Credentials
                // 2. 添加凭据 -> Username with password
                //    - Username: GitHub 用户名
                //    - Password: GitHub Personal Access Token (不是密码)
                //    - ID: github-pat-credentials (或您喜欢的 ID)
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']], // 根据实际分支修改
                    extensions: [
                        [$class: 'CloneOption', depth: 1, noTags: false, shallow: true, timeout: 30],
                        [$class: 'CleanBeforeCheckout'],
                        [$class: 'WipeWorkspace']
                    ],
                    userRemoteConfigs: [[
                        url: 'https://github.com/bobwei192-star/pipeline.git',
                        credentialsId: 'github-pat-credentials'  // 替换为实际的凭据 ID
                    ]]
                ])
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    // 构建 ROCm on Ryzen Docker 镜像
                    sh '''
                        echo "Building ROCm on Ryzen Docker image..."
                        # 添加实际的构建命令
                    '''
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
        failure {
            echo 'Build failed. Please check the logs for details.'
        }
    }
}