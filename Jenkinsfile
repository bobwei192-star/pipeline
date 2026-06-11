/* Jenkinsfile - 使用 withCredentials 注入 GitHub 个人访问令牌 */
/* 需要在 Jenkins 中预先配置 'github-pat' 凭据 (类型: Secret text 或 Username with password) */

pipeline {
    agent any
    
    environment {
        /* 可选：配置 Git 使用凭证助手或显式 URL */
        GIT_URL = 'https://github.com/bobwei192-star/pipeline.git'
    }
    
    options {
        /* 增加检出重试次数 */
        retry(3)
        timeout(time: 30, unit: 'MINUTES')
    }
    
    stages {
        stage('Checkout with Credentials') {
            steps {
                script {
                    /* 方法1: 使用 withCredentials 注入 PAT 到 URL */
                    withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                        /* 清理并重新配置 Git URL 包含令牌 */
                        sh '''
                            git config --global credential.helper store || true
                            git config --global --unset-all http.https://github.com/.extraheader || true
                        '''
                        
                        /* 使用带令牌的 URL 进行检出 */
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main'], [name: '*/master']],
                            extensions: [
                                [$class: 'CloneOption', 
                                 depth: 1, 
                                 noTags: false, 
                                 shallow: true,
                                 timeout: 30
                                ],
                                [$class: 'CleanBeforeCheckout'],
                                [$class: 'WipeWorkspace']
                            ],
                            userRemoteConfigs: [[
                                url: "https://${GITHUB_TOKEN}@github.com/bobwei192-star/pipeline.git",
                                credentialsId: 'github-pat'
                            ]]
                        ])
                    }
                }
            }
        }
        
        stage('Alternative Checkout - Direct Git') {
            /* 如果上述方法失败，使用直接 git 命令 */
            when {
                expression { false }  /* 默认禁用，需要时手动启用 */
            }
            steps {
                script {
                    withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                        sh '''
                            rm -rf .git pipeline || true
                            git clone --depth 1 "https://${GITHUB_TOKEN}@github.com/bobwei192-star/pipeline.git" pipeline || true
                            cp -r pipeline/. .
                            rm -rf pipeline
                        '''
                    }
                }
            }
        }
    }
    
    post {
        failure {
            script {
                echo "检出失败，请检查:"
                echo "1. Jenkins 凭据 'github-pat' 是否已创建"
                echo "2. GitHub PAT 是否有 'repo' 权限"
                echo "3. 仓库 URL 是否正确"
                echo "4. 如果是公开仓库，尝试删除 credentialsId 配置"
            }
        }
    }
}