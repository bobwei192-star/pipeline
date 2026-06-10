/* Jenkinsfile - 使用 SSH 协议替代 HTTPS，或配置凭据绑定 */

// 方案一：如果 Jenkins 已配置 SSH 凭据，使用 SSH URL
// 需要在 Jenkins 凭据管理中配置 SSH private key，ID 为 'github-ssh-key'
pipeline {
    agent any
    
    options {
        // 增加检出重试次数
        checkoutToSubdirectory('src')
        retry(3)
    }
    
    environment {
        // 禁用 Git 交互式提示，避免挂起
        GIT_TERMINAL_PROMPT = '0'
        GIT_SSH_COMMAND = 'ssh -o StrictHostKeyChecking=accept-new'
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    // 检测是否有凭据可用，优先使用 SSH
                    def hasCredentials = false
                    try {
                        withCredentials([sshUserPrivateKey(credentialsId: 'github-ssh-key', keyFileVariable: 'SSH_KEY')]) {
                            hasCredentials = true
                        }
                    } catch (Exception e) {
                        echo "SSH credentials not available, trying HTTPS with token"
                    }
                    
                    if (hasCredentials) {
                        // 使用 SSH URL
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            extensions: [
                                [$class: 'CloneOption', depth: 1, noTags: false, shallow: true],
                                [$class: 'CheckoutOption', timeout: 30]
                            ],
                            userRemoteConfigs: [[
                                url: 'git@github.com:bobwei192-star/pipeline.git',
                                credentialsId: 'github-ssh-key'
                            ]]
                        ])
                    } else {
                        // 回退到 HTTPS，使用 PAT 凭据
                        // 需要在 Jenkins 凭据中配置 'github-pat' 凭据（类型：Secret text，值为 Personal Access Token）
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            extensions: [
                                [$class: 'CloneOption', depth: 1, noTags: false, shallow: true],
                                [$class: 'CheckoutOption', timeout: 30]
                            ],
                            userRemoteConfigs: [[
                                url: 'https://github.com/bobwei192-star/pipeline.git',
                                credentialsId: 'github-pat'
                            ]]
                        ])
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo 'Building ROCm on Ryzen Docker image...'
                // 实际的 Docker 构建步骤
            }
        }
    }
    
    post {
        failure {
            echo 'Build failed. Please verify Git credentials are configured in Jenkins.'
            echo 'Required credentials:'
            echo '  1. github-ssh-key: SSH Username with private key (recommended)'
            echo '  2. github-pat: Secret text with Personal Access Token (alternative)'
            echo ''
            echo 'GitHub PAT setup instructions:'
            echo '  1. Go to https://github.com/settings/tokens'
            echo '  2. Generate new token with "repo" scope'
            echo '  3. Add to Jenkins: Manage Jenkins > Manage Credentials > System > Global credentials'
            echo '  4. Add credential: Kind=Secret text, Secret=<your PAT>, ID=github-pat'
        }
    }
}