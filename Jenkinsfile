pipeline {
    agent any
    options {
        ansiColor('xterm')
        buildDiscarder(logRotator(numToKeepStr: '5', artifactNumToKeepStr: '5'))
    }
    environment {
        GIT_COMMIT_SHORT = sh(
            script: "printf \$(git rev-parse --short ${GIT_COMMIT})",
            returnStdout: true
        )
        POM_VERSION = sh(
            script: "mvn -q -Dexec.executable=echo -Dexec.args='\${project.version}\' --non-recursive exec:exec",
            returnStdout: true
        ).trim()
        BRANCH_NAME_NORMALIZED = sh(
            script: "echo '${BRANCH_NAME}' | sed s#/#-#g",
            returnStdout: true
        ).trim()
        DOCKER_TAG_VERSION = sh(
            script: "echo '${POM_VERSION}' | sed 's/SNAPSHOT/$BRANCH_NAME_NORMALIZED/'",
            returnStdout: true
        ).trim()
    }

    stages {
        stage('Log variables') {
            steps {
                echo "Maven project version: $POM_VERSION"
                echo "Git branch: $BRANCH_NAME"
                echo "Git branch (normalized): $BRANCH_NAME_NORMALIZED"
                echo "Git commit: $GIT_COMMIT"
                echo "Git commit (abbreviated): $GIT_COMMIT_SHORT"
                echo "Docker tag w/ version number: $DOCKER_TAG_VERSION"
            }
        }
        stage('Maven test') {
            steps {
                sh 'mvn clean test'
            }
            post {
                success {
                    junit 'target/surefire-reports/**/*.xml' 
                }
            }
        }
        stage('Build and push Docker image') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'DOCKER_PUBLISHER', passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USER')]) {
                    sh '''
                        mvn clean package -DskipTests -Ddocker.image.tag="$GIT_COMMIT_SHORT" -Ddisplayed-version="$DOCKER_TAG_VERSION"
                        docker login -u "$DOCKER_USER" -p "$DOCKER_PASSWORD" docker.stackable.tech
                        docker push docker.stackable.tech/t2:"$GIT_COMMIT_SHORT"
                        docker logout docker.stackable.tech
                    ''' 
                }            
            }
        }
        stage('Docker: tag with version/branch label') {
            when {
                expression { env.BRANCH_NAME!='main' }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'DOCKER_PUBLISHER', passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USER')]) {
                    sh '''
                        docker tag docker.stackable.tech/t2:"$GIT_COMMIT_SHORT" docker.stackable.tech/t2:"$DOCKER_TAG_VERSION"
                        docker login -u "$DOCKER_USER" -p "$DOCKER_PASSWORD" docker.stackable.tech
                        docker push docker.stackable.tech/t2:"$DOCKER_TAG_VERSION"
                        docker logout docker.stackable.tech
                    ''' 
                }            
            }
        }
        stage('Docker: tag latest') {
            when {
                expression { !env.POM_VERSION.contains('-SNAPSHOT') && env.BRANCH_NAME=='main' }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'DOCKER_PUBLISHER', passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USER')]) {
                    sh '''
                        docker login -u "$DOCKER_USER" -p "$DOCKER_PASSWORD" docker.stackable.tech
                        docker tag docker.stackable.tech/t2:$GIT_COMMIT_SHORT docker.stackable.tech/t2:latest
                        docker push docker.stackable.tech/t2:latest
                        docker logout docker.stackable.tech
                    ''' 
                }            
            }
        }
    }
}
