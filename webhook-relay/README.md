# Webhook Relay

A Rust service that consumes webhooks from AWS SQS and routes them to internal homelab services based on URL path.

## Architecture

```
AWS SQS Queue → webhook-relay → Internal Services (n8n, Gitea, Dagster, etc.)
```

## Features

- **SQS Long Polling**: Efficiently consumes messages from AWS SQS
- **Path-based Routing**: Routes webhooks based on URL path prefix
- **Header Preservation**: Forwards original headers for signature verification
- **Prometheus Metrics**: Exposes metrics for monitoring
- **Health Checks**: Liveness and readiness endpoints

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AWS_REGION` | No | `us-east-1` | AWS region |
| `AWS_ACCESS_KEY_ID` | Yes | - | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | Yes | - | AWS secret key |
| `SQS_QUEUE_URL` | Yes | - | Full SQS queue URL |
| `POLL_INTERVAL_MS` | No | `1000` | Polling interval in ms |
| `MAX_MESSAGES` | No | `10` | Max messages per poll |
| `ROUTE_CONFIG_PATH` | No | `/config/routes.yaml` | Path to routes config |
| `HTTP_PORT` | No | `8080` | Health check port |
| `METRICS_PORT` | No | `9090` | Prometheus metrics port |

### Routes Configuration

See `config/routes.example.yaml` for a complete example.

```yaml
routes:
  n8n:
    url: "https://n8n.example.com/webhook"
    timeout_seconds: 30

  gitea:
    url: "https://gitea.example.com/api/webhooks"
    timeout_seconds: 30

default:
  action: "drop"
```

## Building

### Local Development

```bash
cargo build
cargo run
```

### Docker

```bash
docker build -t webhook-relay .
docker run -p 8080:8080 -p 9090:9090 \
  -e SQS_QUEUE_URL="..." \
  -e AWS_ACCESS_KEY_ID="..." \
  -e AWS_SECRET_ACCESS_KEY="..." \
  -v $(pwd)/config:/config \
  webhook-relay
```

## Endpoints

| Endpoint | Port | Description |
|----------|------|-------------|
| `/health` | 8080 | Liveness probe |
| `/ready` | 8080 | Readiness probe (checks SQS) |
| `/metrics` | 9090 | Prometheus metrics |

## Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `webhook_relay_messages_received_total` | Counter | - | Messages received from SQS |
| `webhook_relay_messages_forwarded_total` | Counter | target, status | Messages forwarded |
| `webhook_relay_messages_failed_total` | Counter | target, reason | Failed messages |
| `webhook_relay_forward_duration_seconds` | Histogram | target | Forward latency |

## Message Format

The service expects SQS messages in this format (produced by the Lambda transformer):

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
