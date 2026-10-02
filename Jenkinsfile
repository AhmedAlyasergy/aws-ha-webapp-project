pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                echo 'Code checked out from GitHub'
            }
        }

        stage('Validate') {
            steps {
                echo 'Validating AWS HA Web App project...'
                sh 'ls -la'
            }
        }

        stage('Build') {
            steps {
                echo 'Build stage completed'
            }
        }

        stage('Test') {
    steps {
        echo 'Running tests...'
        sh 'test -f cloudformation-stack.yaml'
        sh 'test -f user-data.sh'
        echo 'Required project files exist.'
    }
}
    }

    post {
        success {
            echo 'CI Pipeline completed successfully!'
        }

        failure {
            echo 'CI Pipeline failed.'
        }
    }
}
