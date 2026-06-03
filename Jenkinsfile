// Jenkins Pipeline — clone test_case 并执行验证
// 
// 变更说明:
//   - 添加 GitLab 凭据认证
//   - 使用正确的 GitLab 端口

pipeline {
    agent any

    stages {
        stage('Clone') {
            steps {
                echo 'Cloning test_case repository...'
                sh 'git config --global http.sslVerify false'
                git branch: 'main',
                    url: 'https://root:glpat--Up_H6JZgkvoJGjINmPE6G86MQp1OjEH.01.0w094ajv4@172.21.201.77:18441/root/test_case.git'
            }
        }

        stage('Verify') {
            steps {
                echo 'Verifying repository contents...'
                sh 'ls -la'
                sh 'cat repo_name.md'
            }
        }
    }
}
