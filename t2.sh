#!/bin/bash

echo "Starting T2..."

# Config file must be present (usually as mounted volume)
if [[ ! -f "/var/t2/t2-config.yaml" ]]; then
    echo "Error: Please supply a config file in /var/t2/t2-config.yaml"
    exit 1
fi
echo "Config file supplied: /var/t2/t2-config.yaml"

# Security Token to access T2
SECURITY_TOKEN=`cat /var/t2/t2-config.yaml | yq -e '.security-token' 2>/dev/null`
if [ ! $? -ne 0 ]; then
	export SECURITY_TOKEN=$SECURITY_TOKEN
else
    echo "Error: Please supply a security-token in the T2 config file."
    exit 1
fi

echo "SECURITY_TOKEN supplied"

# Initialize everything we need to access the cloud providers

# Hetzner / HCloud
# The HCloud token is provided to Terraform as an environment variable
export TF_VAR_hcloud_token=`cat /var/t2/t2-config.yaml | yq -e '.hcloud.token' 2>/dev/null`
echo "HCloud credentials set as environment variables for Terraform."

# IONOS Cloud
# The IONOS username/password are provided to Terraform as environment variables
export TF_VAR_ionos_username=`cat /var/t2/t2-config.yaml | yq -e '.ionos.username' 2>/dev/null`
export TF_VAR_ionos_password=`cat /var/t2/t2-config.yaml | yq -e '.ionos.password' 2>/dev/null`
echo "IONOS Cloud credentials set as environment variables for Terraform."

# Azure
# Azure keys are provided to Terraform as environment variables
export TF_VAR_az_subscription_id=`cat /var/t2/t2-config.yaml | yq -e '.azure.subscription-id' 2>/dev/null`
export TF_VAR_az_subscription_tenant_id=`cat /var/t2/t2-config.yaml | yq -e '.azure.subscription-tenant-id' 2>/dev/null`
export TF_VAR_az_service_principal_app_id=`cat /var/t2/t2-config.yaml | yq -e '.azure.service-principal-app-id' 2>/dev/null`
export TF_VAR_az_service_principal_password=`cat /var/t2/t2-config.yaml | yq -e '.azure.service-principal-password' 2>/dev/null`
echo "Microsoft Azure credentials set as environment variables for Terraform."

# AWS
# AWS keys are provided to Terraform as environment variables
export TF_VAR_aws_access_key=`cat /var/t2/t2-config.yaml | yq -e '.aws.access-key' 2>/dev/null`
export TF_VAR_aws_secret_access_key=`cat /var/t2/t2-config.yaml | yq -e '.aws.secret-access-key' 2>/dev/null`
export AWS_REGION=`cat /var/t2/t2-config.yaml | yq -e '.aws.region' 2>/dev/null`
echo "AWS credentials set as environment variables for Terraform."

aws configure set aws_access_key_id $TF_VAR_aws_access_key && \
    aws configure set aws_secret_access_key $TF_VAR_aws_secret_access_key && \
    aws configure set region $AWS_REGION

echo "AWS CLI login:"
aws sts get-caller-identity

# Google Cloud
# Project-ID is provided to Terraform as environment variable
export TF_VAR_google_cloud_project_id=`cat /var/t2/t2-config.yaml | yq -e '.gcloud.project-id' 2>/dev/null`

# Extract credential file for glcoud CLI from T2 config
cat /var/t2/t2-config.yaml | yq -e '.gcloud.cred-file' 2>/dev/null > /var/t2/gcloud-credentials.json

# let environment variable point to GCloud credential file for use in Terraform
export GOOGLE_APPLICATION_CREDENTIALS=/var/t2/gcloud-credentials.json

# Log into GCloud
gcloud auth login --cred-file=/var/t2/gcloud-credentials.json

echo "GCloud CLI login:"
gcloud info

# Start Java application
# 'exec' => java process takes over and gets the signals

echo "Starting T2 Java application..."
exec java -Djava.security.egd=file:/dev/./urandom -Dspring.profiles.active=docker -jar /var/t2/t2-server.jar
