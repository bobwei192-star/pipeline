pipeline {
    agent any
    
    options {
        // 增加检出重试次数
        checkoutRetryCount(3)
    }
    
    environment {
        // 使用 GIT_URL 环境变量便于配置
        GIT_URL = 'https://github.com/bobwei192-star/pipeline.git'
    }
    
    stages {
        stage('Checkout with Credentials') {
            steps {
                script {
                    // 尝试使用凭证 ID 'github-pat' 检出代码
                    // 需要在 Jenkins 中预先配置 Personal Access Token 凭证
                    // 凭证配置路径: Jenkins Dashboard -> Manage Jenkins -> Credentials -> System -> Global credentials -> Add Credentials
                    // Kind: 'Username with password'
                    // Username: GitHub 用户名
                    // Password: GitHub Personal Access Token (classic 或 fine-grained)
                    // ID: github-pat
                    
                    // 首先尝试使用凭证检出
                    try {
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            extensions: [],
                            userRemoteConfigs: [[
                                url: env.GIT_URL,
                                credentialsId: 'github-pat'
                            ]]
                        ])
                    } catch (Exception e) {
                        echo "Failed to checkout with credentialsId 'github-pat': ${e.getMessage()}"
                        
                        // 备选方案：尝试其他常见凭证 ID
                        def credentialIds = ['github-token', 'github-credentials', 'git-credentials', 'pipeline-github-token']
                        def checkoutSuccess = false
                        
                        for (credId in credentialIds) {
                            try {
                                echo "Trying credential ID: ${credId}"
                                checkout([
                                    $class: 'GitSCM',
                                    branches: [[name: '*/main']],
                                    extensions: [],
                                    userRemoteConfigs: [[
                                        url: env.GIT_URL,
                                        credentialsId: credId
                                    ]]
                                ])
                                checkoutSuccess = true
                                echo "Successfully checked out using credential ID: ${credId}"
                                break
                            } catch (Exception ex) {
                                echo "Credential ID ${credId} failed: ${ex.getMessage()}"
                                continue
                            }
                        }
                        
                        if (!checkoutSuccess) {
                            error """
                                GitHub 认证失败。请按以下步骤配置凭证：
                                
                                1. 生成 GitHub Personal Access Token:
                                   - 访问 https://github.com/settings/tokens
                                   - 点击 'Generate new token (classic)'
                                   - 选择权限: repo (完整仓库访问)
                                   - 生成并复制 Token
                                
                                2. 在 Jenkins 中配置凭证:
                                   - Manage Jenkins -> Manage Credentials
                                   - 选择适当域 (通常 Global)
                                   - Add Credentials
                                   - Kind: Username with password
                                   - Username: 您的 GitHub 用户名
                                   - Password: 粘贴生成的 PAT
                                   - ID: github-pat (或修改 Jenkinsfile 中的 credentialsId)
                                   - Description: GitHub PAT for pipeline repo
                                
                                3. 如果是公共仓库但当前被识别为私有，请检查仓库可见性设置
                                
                                原始错误: ${e.getMessage()}
                            """.stripIndent()
                        }
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo 'Building ROCm on Ryzen Docker image...'
                // 原有的 Docker 构建步骤
                sh '''
                    echo "Docker build steps would go here"
                    # docker build -t rocm-ryzen:latest .
                '''
            }
        }
    }
    
    post {
        failure {
            script {
                echo "Build failed. Checking common issues..."
                
                // 诊断信息
                sh '''
                    echo "=== Git Configuration ==="
                    git config --list || true
                    
                    echo "=== Network Connectivity ==="
                    curl -I https://github.com 2>/dev/null | head -5 || true
                    
                    echo "=== Git Version ==="
                    git --version || true
                '''
            }
        }
    }
}