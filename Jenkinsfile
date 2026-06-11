pipeline {
    agent any
    
    environment {
        // 使用 Jenkins 凭据存储中的 GitHub PAT
        // 需要在 Jenkins 中预先配置凭据 ID 为 'github-pat' 的 Secret text 凭据
        GITHUB_CREDENTIALS = credentials('github-pat')
    }
    
    options {
        // 设置 SCM 检出重试次数
        checkoutRetryCount(3)
        // 禁用默认检出，使用自定义检出步骤
        skipDefaultCheckout(true)
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    // 使用凭据进行 Git 检出
                    // 需要在 Jenkins 中配置凭据 ID，这里使用 'github-pat' 作为示例
                    // 实际使用时需要在 Jenkins 中创建对应凭据
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
        
        stage('Build') {
            steps {
                echo 'Building...'
                // 添加实际的构建步骤
            }
        }
    }
    
    post {
        failure {
            echo 'Build failed. Please check GitHub credentials configuration.'
            echo 'Ensure Jenkins credential with ID "github-pat" exists and contains a valid GitHub Personal Access Token.'
        }
    }
}