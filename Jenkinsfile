pipeline {
    agent any
    
    options {
        // 增加 SCM 检出重试次数
        checkoutRetryCount(5)
        // 设置超时时间
        timeout(time: 30, unit: 'MINUTES')
    }
    
    environment {
        // 使用环境变量传递凭据 ID，便于不同环境配置
        GIT_CREDENTIALS_ID = credentials('github-pat-credentials')
    }
    
    stages {
        stage('Checkout with Credentials') {
            steps {
                script {
                    // 尝试使用凭据检出代码
                    // 需要在 Jenkins 凭据管理中预先配置 'github-pat-credentials'
                    // 凭据类型: Username with password
                    // Username: GitHub 用户名
                    // Password: GitHub Personal Access Token (classic 或 fine-grained)
                    // Token 权限需要: repo (访问私有仓库)
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],  // 根据实际分支修改
                        extensions: [
                            [$class: 'CloneOption', 
                             depth: 1, 
                             noTags: false, 
                             shallow: true,
                             timeout: 30],
                            [$class: 'CheckoutOption', timeout: 30],
                            // 清理工作区避免冲突
                            [$class: 'CleanBeforeCheckout'],
                            [$class: 'WipeWorkspace']
                        ],
                        userRemoteConfigs: [[
                            url: 'https://github.com/bobwei192-star/pipeline.git',
                            credentialsId: 'github-pat-credentials'
                        ]]
                    ])
                }
            }
        }
        
        // 如果上述方式失败，提供备选方案：使用 GitHub App 凭据
        stage('Alternative: GitHub App Checkout') {
            when {
                expression { currentBuild.result == 'FAILURE' }
            }
            steps {
                script {
                    // 备选：使用 GitHub App 凭据（更安全的推荐方式）
                    // 需要在 Jenkins 凭据管理中配置 GitHub App 凭据
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],
                        extensions: [
                            [$class: 'CloneOption', depth: 1, shallow: true, timeout: 30]
                        ],
                        userRemoteConfigs: [[
                            url: 'https://github.com/bobwei192-star/pipeline.git',
                            credentialsId: 'github-app-credentials'
                        ]]
                    ])
                }
            }
        }
    }
    
    post {
        failure {
            echo '构建失败，可能原因：'
            echo '1. 凭据 ID 不存在或配置错误'
            echo '2. GitHub PAT 已过期或被撤销'
            echo '3. PAT 权限不足（需要 repo 权限）'
            echo '4. 仓库 URL 错误或仓库不存在/不可访问'
            echo ''
            echo '修复步骤：'
            echo '1. 在 Jenkins 中创建凭据：Manage Jenkins > Manage Credentials'
            echo '2. 添加 "Username with password" 类型凭据'
            echo '3. Username: GitHub 用户名'
            echo '4. Password: GitHub Personal Access Token（不是登录密码）'
            echo '5. 生成 PAT: GitHub Settings > Developer settings > Personal access tokens'
            echo '6. 确保 PAT 有 repo 权限'
        }
    }
}