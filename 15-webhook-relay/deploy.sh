#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

NAMESPACE="webhook-relay"
IMAGE="${WEBHOOK_RELAY_IMAGE:-harbor.apps.house.simonellistonball.com/library/webhook-relay:latest}"
REGISTRY="harbor.apps.house.simonellistonball.com"

echo "============================================"
echo "  Webhook Relay Deployment"
echo "============================================"
echo ""

# Check required variables
if [ -z "${AWS_WEBHOOK_QUEUE_URL:-}" ]; then
    echo "ERROR: AWS_WEBHOOK_QUEUE_URL is not set in config.env"
    echo "Deploy the AWS infrastructure first: cd aws && ./deploy.sh"
    exit 1
fi

if [ -z "${AWS_WEBHOOK_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_WEBHOOK_SECRET_ACCESS_KEY:-}" ]; then
    echo "ERROR: AWS credentials not set in config.env"
    echo "Required: AWS_WEBHOOK_ACCESS_KEY_ID and AWS_WEBHOOK_SECRET_ACCESS_KEY"
    exit 1
fi

echo "Using image: ${IMAGE}"
echo "SQS Queue: ${AWS_WEBHOOK_QUEUE_URL}"
echo ""

# Create namespace
echo "Creating namespace..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Create certificate
echo "Creating certificate..."
kubectl apply -f "${SCRIPT_DIR}/certificate.yaml"

# Create secrets
echo "Creating secrets..."
kubectl create secret generic webhook-relay-aws \
    --namespace ${NAMESPACE} \
    --from-literal=AWS_ACCESS_KEY_ID="${AWS_WEBHOOK_ACCESS_KEY_ID}" \
    --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_WEBHOOK_SECRET_ACCESS_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create registry pull secret
echo "Creating registry pull secret..."
kubectl create secret docker-registry harbor-pull-secret \
    --namespace ${NAMESPACE} \
    --docker-server="${REGISTRY}" \
    --docker-username="${HARBOR_PULL_USER}" \
    --docker-password="${HARBOR_PULL_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Wait for certificate
echo "Waiting for certificate..."
kubectl wait --for=condition=Ready certificate/webhook-relay-cert -n ${NAMESPACE} --timeout=120s || true

# Create routes ConfigMap
echo "Creating routes ConfigMap..."
kubectl apply -f "${SCRIPT_DIR}/configmap.yaml"

# Apply substitutions to deployment
TMP_DEPLOY=$(mktemp)
trap "rm -f $TMP_DEPLOY" EXIT

sed -e "s|IMAGE_PLACEHOLDER|${IMAGE}|g" \
    -e "s|QUEUE_URL_PLACEHOLDER|${AWS_WEBHOOK_QUEUE_URL}|g" \
    -e "s|AWS_REGION_PLACEHOLDER|${AWS_WEBHOOK_REGION:-us-east-1}|g" \
    "${SCRIPT_DIR}/deployment.yaml" > "$TMP_DEPLOY"

# Apply resources
echo "Applying Kubernetes resources..."
kubectl apply -f "$TMP_DEPLOY"
kubectl apply -f "${SCRIPT_DIR}/service.yaml"
kubectl apply -f "${SCRIPT_DIR}/servicemonitor.yaml"
kubectl apply -f "${SCRIPT_DIR}/ingressroute.yaml"

# Wait for deployment
echo ""
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/webhook-relay -n ${NAMESPACE} --timeout=300s

echo ""
echo "============================================"
echo "  Deployment Complete"
echo "============================================"
echo ""
echo "Pod status:"
kubectl get pods -n ${NAMESPACE}
echo ""
echo "Metrics URL: https://webhook-relay.${DOMAIN}/metrics (internal only)"
echo ""
echo "To view logs:"
echo "  kubectl logs -f -n ${NAMESPACE} -l app=webhook-relay"
echo ""
echo "To test health:"
echo "  kubectl exec -n ${NAMESPACE} deploy/webhook-relay -- curl -s localhost:8080/health"
