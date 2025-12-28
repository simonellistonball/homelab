#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
STACK_NAME="${STACK_NAME:-webhook-ingestion}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "  Webhook Ingestion - AWS Deployment"
echo "============================================"
echo ""
echo "Stack Name:  ${STACK_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Region:      ${AWS_REGION}"
echo ""

# Check AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed."
    echo "Install it: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "ERROR: AWS credentials not configured or invalid."
    echo "Run: aws configure"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account: ${ACCOUNT_ID}"
echo ""

# Deploy or update the stack
echo "Deploying CloudFormation stack..."
aws cloudformation deploy \
    --stack-name "${STACK_NAME}" \
    --template-file "${SCRIPT_DIR}/cloudformation/webhook-ingestion.yaml" \
    --parameter-overrides Environment="${ENVIRONMENT}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${AWS_REGION}" \
    --no-fail-on-empty-changeset

echo ""
echo "Waiting for stack to complete..."
aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}" --region "${AWS_REGION}" 2>/dev/null || \
aws cloudformation wait stack-update-complete --stack-name "${STACK_NAME}" --region "${AWS_REGION}" 2>/dev/null || true

# Get outputs
echo ""
echo "============================================"
echo "  Stack Outputs"
echo "============================================"
echo ""

get_output() {
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${AWS_REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
        --output text
}

WEBHOOK_URL=$(get_output "WebhookUrl")
QUEUE_URL=$(get_output "WebhookQueueUrl")
ACCESS_KEY_ID=$(get_output "WebhookRelayAccessKeyId")
SECRET_ACCESS_KEY=$(get_output "WebhookRelaySecretAccessKey")
API_ENDPOINT=$(get_output "WebhookApiEndpoint")

echo "Webhook URL:      ${WEBHOOK_URL}"
echo "API Endpoint:     ${API_ENDPOINT}"
echo "SQS Queue URL:    ${QUEUE_URL}"
echo ""
echo "============================================"
echo "  Credentials for webhook-relay"
echo "============================================"
echo ""
echo "Add these to your homelab config.env:"
echo ""
echo "export AWS_WEBHOOK_REGION=\"${AWS_REGION}\""
echo "export AWS_WEBHOOK_ACCESS_KEY_ID=\"${ACCESS_KEY_ID}\""
echo "export AWS_WEBHOOK_SECRET_ACCESS_KEY=\"${SECRET_ACCESS_KEY}\""
echo "export AWS_WEBHOOK_QUEUE_URL=\"${QUEUE_URL}\""
echo ""
echo "============================================"
echo "  Webhook URL Format"
echo "============================================"
echo ""
echo "Configure external services to send webhooks to:"
echo ""
echo "  ${WEBHOOK_URL}/<service>/<path>"
echo ""
echo "Examples:"
echo "  ${WEBHOOK_URL}/n8n/my-workflow"
echo "  ${WEBHOOK_URL}/gitea/push"
echo "  ${WEBHOOK_URL}/dagster/sensor/github"
echo ""
echo "Deployment complete!"
