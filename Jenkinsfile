pipeline {
    agent any
    
    environment {
        // Harbor 配置
        HARBOR_URL = '172.21.201.77:18446'
        HARBOR_PROJECT = 'rocm_and_model_env'
        IMAGE_NAME = 'rocm-ryzen-image'
        IMAGE_TAG = "${BUILD_NUMBER}"
        
        // BuildAgent 仓库（开源，无需凭据）
        BUILD_REPO = 'https://github.com/bobwei192-star/build.git'
    }
    
    stages {
        stage('Checkout BuildAgent') {
            steps {
                script {
                    echo "🔄 Cloning BuildAgent repository..."
                    sh """
                        rm -rf build-agent-temp
                        git clone ${BUILD_REPO} build-agent-temp
                        ls -la build-agent-temp/
                    """
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    echo "🐳 Building Docker image..."
                    sh """
                        cd build-agent-temp
                        
                        # 构建镜像
                        docker build -t ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG} .
                        
                        # 标记为 latest
                        docker tag ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG} ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:latest
                    """
                }
            }
        }
        
        stage('Push to Harbor') {
            steps {
                script {
                    echo "📤 Pushing image to Harbor..."
                    // 使用 Jenkins 凭据
                    withCredentials([usernamePassword(credentialsId: 'harbor-credentials', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS')]) {
                        sh """
                            # 登录 Harbor
                            echo "${HARBOR_PASS}" | docker login ${HARBOR_URL} -u ${HARBOR_USER} --password-stdin
                            
                            # 推送镜像
                            docker push ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:latest
                            
                            echo "✅ Image pushed successfully!"
                        """
                    }
                }
            }
        }
        
        stage('Verify') {
            steps {
                script {
                    echo "🔍 Verifying image in Harbor..."
                    sh """
                        # 清理本地镜像
                        docker rmi ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG} || true
                        docker rmi ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:latest || true
                        
                        echo "✅ Build ${BUILD_NUMBER} completed successfully!"
                        echo "Image: ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}"
                    """
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "🧹 Cleaning up..."
                sh """
                    rm -rf build-agent-temp || true
                """
            }
        }
        success {
            echo "🎉 Pipeline succeeded!"
        }
        failure {
            echo "❌ Pipeline failed!"
        }
    }
}