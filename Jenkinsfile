pipeline {
    agent any
    
    options {
        // 增加检出重试次数
        checkoutRetryCount(3)
    }
    
    environment {
        // 使用环境变量传递 GitHub Token
        // 需要在 Jenkins 中配置 Credentials: 类型为 'Secret text' 的 GITHUB_TOKEN
        GIT_URL = 'https://github.com/bobwei192-star/pipeline.git'
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    // 尝试使用凭证检出，回退到无凭证（仅公共仓库）
                    try {
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            extensions: [
                                [$class: 'CloneOption', 
                                 depth: 1, 
                                 noTags: false, 
                                 shallow: true,
                                 timeout: 30],
                                [$class: 'Retry', 
                                 retries: 3]
                            ],
                            userRemoteConfigs: [[
                                url: "${env.GIT_URL}",
                                credentialsId: 'github-token-credentials'  // 替换为实际的 Jenkins credentials ID
                            ]]
                        ])
                    } catch (Exception e) {
                        echo "Checkout with credentials failed, trying without credentials for public repo: ${e.getMessage()}"
                        // 对于公共仓库，尝试无凭证检出
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            extensions: [
                                [$class: 'CloneOption', 
                                 depth: 1, 
                                 noTags: false, 
                                 shallow: true,
                                 timeout: 30]
                            ],
                            userRemoteConfigs: [[
                                url: "${env.GIT_URL}"
                            ]]
                        ])
                    }
                }
            }
        }
        
        stage('Verify Git Access') {
            steps {
                script {
                    // 验证 Git 配置
                    sh '''
                        echo "Git version: $(git --version)"
                        echo "Git remote URL: $(git remote get-url origin 2>/dev/null || echo 'No remote configured')"
                        echo "Current branch: $(git branch --show-current 2>/dev/null || echo 'Detached HEAD')"
                    '''
                }
            }
        }
        
        // 原有构建阶段...
        stage('Build Docker Image') {
            steps {
                echo 'Building ROCm on Ryzen Docker image...'
                // 添加实际的 Docker 构建命令
                // sh 'docker build -t rocm-ryzen:latest .'
            }
        }
    }
    
    post {
        failure {
            script {
                echo "Build failed. Common fixes:"
                echo "1. Ensure 'github-token-credentials' exists in Jenkins Credentials (type: Secret text or Username with password)"
                echo "2. For Secret text: use Personal Access Token as the secret"
                echo "3. For Username with password: use 'token' or your username as username, PAT as password"
                echo "4. Verify the GitHub token has 'repo' scope for private repositories"
                echo "5. Alternative: Switch to SSH URL (git@github.com:bobwei192-star/pipeline.git) with SSH credentials"
            }
        }
    }
}