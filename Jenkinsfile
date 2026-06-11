pipeline {
    agent any
    
    options {
        // 增加 Git 检出重试次数
        checkoutRetryCount(3)
    }
    
    environment {
        // 设置 Git 使用 credential helper 避免交互式提示
        GIT_TERMINAL_PROMPT = '0'
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    // 尝试使用多种凭证 ID 进行检出，按优先级尝试
                    def credentialIds = [
                        'github-pat-token',      // 首选：GitHub Personal Access Token
                        'github-credentials',       // 备选：通用凭证
                        'github-token',           // 备选：其他命名
                        'bobwei192-star-github'   // 备选：用户特定凭证
                    ]
                    
                    def checkoutSuccess = false
                    
                    for (credId in credentialIds) {
                        try {
                            echo "Trying credential ID: ${credId}"
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: '*/main']],
                                extensions: [
                                    [$class: 'CloneOption', timeout: 60],
                                    [$class: 'Retry', retries: 3]
                                ],
                                userRemoteConfigs: [[
                                    url: 'https://github.com/bobwei192-star/pipeline.git',
                                    credentialsId: credId
                                ]]
                            ])
                            echo "Successfully checked out with credential: ${credId}"
                            checkoutSuccess = true
                            break
                        } catch (Exception e) {
                            echo "Checkout failed with credential ${credId}: ${e.getMessage()}"
                            continue
                        }
                    }
                    
                    if (!checkoutSuccess) {
                        // 最后尝试无凭证检出（仅公开仓库）
                        echo "Attempting checkout without credentials (public repo only)..."
                        try {
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: '*/main']],
                                extensions: [[$class: 'CloneOption', timeout: 60]],
                                userRemoteConfigs: [[
                                    url: 'https://github.com/bobwei192-star/pipeline.git'
                                ]]
                            ])
                            echo "Public checkout succeeded"
                        } catch (Exception e) {
                            error "All checkout attempts failed. Please configure GitHub credentials in Jenkins. " +
                                  "Required steps: 1) Generate PAT at https://github.com/settings/tokens " +
                                  "2) Add credential in Jenkins (Manage Jenkins > Credentials) " +
                                  "3) Update Jenkinsfile with correct credentialsId"
                        }
                    }
                }
            }
        }
        
        stage('Build ROCm Docker Image') {
            steps {
                echo 'Building ROCm Docker image on Ryzen...'
                // 实际的镜像构建步骤
            }
        }
    }
    
    post {
        failure {
            echo 'Build failed. Common causes:'
            echo '1. Missing GitHub credentials in Jenkins'
            echo '2. Expired/invalid Personal Access Token'
            echo '3. Insufficient permissions for the repository'
            echo ''
            echo 'To fix: Go to Jenkins > Manage Jenkins > Credentials > System > Global credentials'
            echo 'Add a new credential:'
            echo '  - Kind: Username with password'
            echo '  - Username: your-github-username'
            echo '  - Password: your-github-personal-access-token'
            echo '  - ID: github-pat-token'
        }
    }
}