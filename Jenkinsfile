pipeline {
    agent any

    environment {
        // 定义凭据 ID，需要在 Jenkins -> Credentials 中预先配置
        // 类型建议: Username with password (GitHub 用户名 + Personal Access Token)
        GITHUB_CREDS = credentials('github-pipeline-creds')
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    // 使用 withCredentials 绑定凭据进行 Git 操作
                    // 或者直接在 checkout 步骤中指定 credentialsId
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/main']], // 请根据实际分支修改，如 master 或 main
                        doGenerateSubmoduleConfigurations: false,
                        extensions: [],
                        submoduleCfg: [],
                        userRemoteConfigs: [[
                            url: 'https://github.com/bobwei192-star/pipeline.git',
                            // 关键修复: 添加 credentialsId
                            credentialsId: 'github-pipeline-creds'
                        ]]
                    ])
                }
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                script {
                    echo "Building Docker Image..."
                    // 此处为原有构建逻辑占位符
                    // sh 'docker build -t rocm-on-ryzen .'
                    // sh 'docker push ...'
                }
            }
        }
    }
}