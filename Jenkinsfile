pipeline {
    agent any
    
    // 定义 Git 凭据 - 需要在 Jenkins 中预先配置好凭据
    // 请先在 Jenkins 凭据管理器中创建以下凭据之一：
    // 1. Username with Password: 用户名填 GitHub 用户名，密码填 Personal Access Token (PAT)
    // 2. Secret file: SSH 私钥文件
    // 然后在 environment 块或 checkout 步骤中引用
    
    environment {
        // 使用 Jenkins 凭据 ID，请替换为实际的凭据 ID
        // 推荐在 Jenkins 凭据管理器中创建 'github-pat' 或类似名称的凭据
        GIT_CREDENTIALS = credentials('github-pat')
    }
    
    stages {
        stage('Checkout') {
            steps {
                // 方式一：使用显式凭据进行 checkout（推荐）
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],  // 根据实际情况调整分支
                    extensions: [],
                    userRemoteConfigs: [[
                        url: 'https://github.com/bobwei192-star/pipeline.git',
                        credentialsId: 'github-pat'  // 替换为 Jenkins 中实际配置的凭据 ID
                    ]]
                ])
            }
        }
        
        // 或者使用更简洁的方式（如果已在 Jenkins 作业配置中设置）
        // stage('Checkout Simple') {
        //     steps {
        //         git branch: 'main',
        //            credentialsId: 'github-pat',
        //            url: 'https://github.com/bobwei192-star/pipeline.git'
        //     }
        // }
        
        stage('Build') {
            steps {
                echo 'Starting build...'
                // 添加实际的构建步骤
            }
        }
    }
    
    post {
        always {
            echo 'Pipeline finished'
        }
        failure {
            echo 'Pipeline failed - please check Git credentials configuration'
        }
    }
}