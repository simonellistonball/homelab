# AWS Webhook Ingestion Infrastructure

This directory contains AWS infrastructure for receiving webhooks from external services and queueing them for the homelab webhook-relay service.

## Architecture

```
External Services → API Gateway → Lambda → SQS Queue → webhook-relay (homelab)
```

- **API Gateway HTTP API**: Receives webhook POST requests
- **Lambda Function**: Transforms requests to capture headers, path, body, etc.
- **SQS Queue**: Buffers messages for reliable delivery
- **Dead Letter Queue**: Captures failed messages for debugging

## Prerequisites

1. AWS CLI installed and configured:
   ```bash
   aws configure
   ```

2. Sufficient IAM permissions to create:
   - CloudFormation stacks
   - API Gateway
   - Lambda functions
   - SQS queues
   - IAM users and roles

## Deployment

```bash
# Deploy with defaults (us-east-1, prod environment)
./deploy.sh

# Or customize
AWS_REGION=eu-west-1 ENVIRONMENT=dev ./deploy.sh
```

## Outputs

After deployment, the script outputs:
- **Webhook URL**: Base URL for external services
- **SQS Queue URL**: For the webhook-relay service
- **Access credentials**: AWS credentials for the relay service

## Webhook URL Format

External services should send webhooks to:
```
https://<api-id>.execute-api.<region>.amazonaws.com/webhook/<service>/<path>
```

### Examples

| Service | Webhook URL |
|---------|-------------|
| GitHub → n8n | `.../webhook/n8n/github-events` |
| Stripe → n8n | `.../webhook/n8n/stripe-payments` |
| Slack → custom | `.../webhook/slack/interactive` |
| Monitoring | `.../webhook/dagster/alerts` |

## Message Format

Messages in SQS have this structure:

```json
{
  "path": "/webhook/n8n/my-workflow",
  "method": "POST",
  "headers": {
    "content-type": "application/json",
    "x-github-event": "push"
  },
  "body": "{...}",
  "isBase64Encoded": false,
  "queryStringParameters": {},
  "timestamp": "2025-01-15T10:30:00Z",
  "sourceIp": "192.0.2.1"
}
```

## Cleanup

To delete the stack:

```bash
aws cloudformation delete-stack --stack-name webhook-ingestion
```

Note: This will delete the IAM user and invalidate any access keys.

## Cost Estimate

For typical homelab usage (< 100k webhooks/month):
- API Gateway: ~$0.35/million requests
- Lambda: Free tier covers it
- SQS: Free tier covers it

**Expected monthly cost: < $1**
