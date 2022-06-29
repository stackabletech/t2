#!/bin/bash

function getProperty {
    cat /var/t2/credentials.properties | grep $1 | cut -d'=' -f2 | tr -d '"'
}

AWS_ACCESS_KEY_ID=$(getProperty 'aws_access_key')
AWS_SECRET_ACCESS_KEY_ID=$(getProperty 'aws_secret_access_key')

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID && \
    aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY_ID && \
    aws configure set region eu-central-1
