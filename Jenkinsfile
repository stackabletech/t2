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
        DISPLAY_VERSION = sh(
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
                echo "displayed version: $DISPLAY_VERSION"
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

        // for all builds: a Docker image tagged with the abbreviated Git commit # is built and pushed
        stage('Build and push Docker image') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'DOCKER_PUBLISHER', passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USER')]) {
                    sh '''
                        T2_DISPLAY_VERSION="$DISPLAY_VERSION" mvn clean package -DskipTests
                        docker login -u "$DOCKER_USER" -p "$DOCKER_PASSWORD" docker.stackable.tech
                        docker push docker.stackable.tech/t2:"$GIT_COMMIT_SHORT"
                        docker logout docker.stackable.tech
                    ''' 
                }            
            }
        }

        // The Docker image is tagged with a version-label for ...
        // - ... all SNAPSHOT builds 
        // - ... RELEASE-builds ONLY on main branch (to prevent releasing from other branches)
        stage('Docker: tag with version/branch label') {
            when {
                expression { env.POM_VERSION.contains('-SNAPSHOT') || env.BRANCH_NAME=='main' }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'DOCKER_PUBLISHER', passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USER')]) {
                    sh '''
                        docker tag docker.stackable.tech/t2:"$GIT_COMMIT_SHORT" docker.stackable.tech/t2:"$DISPLAY_VERSION"
                        docker login -u "$DOCKER_USER" -p "$DOCKER_PASSWORD" docker.stackable.tech
                        docker push docker.stackable.tech/t2:"$DISPLAY_VERSION"
                        docker logout docker.stackable.tech
                    ''' 
                }            
            }
        }

        // The Docker image is tagged as 'latest' ONLY IF the version is not a SNAPSHOT version AND we build the main branch
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
