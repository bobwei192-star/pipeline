pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                // 修复说明：
                // 1. 显式指定 credentialsId，替换 'YOUR_GITHUB_CREDENTIALS_ID' 为 Jenkins 中配置的实际凭据 ID。
                //    凭据类型应为 'Username with password' (用户名 + Personal Access Token)。
                // 2. 显式指定分支，避免默认行为带来的不确定性。
                git url: 'https://github.com/bobwei192-star/pipeline.git', 
                    branch: 'main', 
                    credentialsId: 'github-credentials-id'
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    echo 'Building Docker image...'
                    // 此处保留原有的构建逻辑
                }
            }
        }
    }
}
