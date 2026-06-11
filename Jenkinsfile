pipeline {
    agent any
    
    environment {
        // 使用环境变量存储Git凭证，避免硬编码
        GIT_URL = 'https://github.com/bobwei192-star/pipeline.git'
    }
    
    stages {
        stage('Checkout') {
            steps {
                // 方式1: 使用Jenkins凭证ID（推荐）
                // 需要在Jenkins中预先配置凭证，然后替换'your-credentials-id'为实际ID
                checkout scmGit(
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[
                        url: env.GIT_URL,
                        credentialsId: 'github-pat-credentials'
                    ]]
                )
                
                // 方式2: 如果凭证ID不同，请修改上面的credentialsId
                // 常用凭证ID命名: 'github-token', 'github-pat', 'git-credentials'
            }
        }
        
        // 其他构建阶段...
    }
}