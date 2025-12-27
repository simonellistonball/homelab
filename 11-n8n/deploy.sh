#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Deploying n8n..."

# Create namespace
kubectl create namespace n8n --dry-run=client -o yaml | kubectl apply -f -

# Create certificate first
kubectl apply -f certificate.yaml

# Create secrets
kubectl create secret generic n8n-secrets \
  --namespace n8n \
  --from-literal=DB_POSTGRESDB_PASSWORD="${POSTGRES_N8N_PASSWORD}" \
  --from-literal=N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Note: Root CA trust is automatically distributed by trust-manager
# via the simonellistonball-ca-bundle ConfigMap

# Wait for certificate to be ready
echo "Waiting for certificate to be ready..."
kubectl wait --for=condition=Ready certificate/n8n-cert -n n8n --timeout=120s

# Substitute config values in deployment
TMP_DEPLOY=$(mktemp)
trap "rm -f $TMP_DEPLOY" EXIT

sed "s/POSTGRES_HOST_PLACEHOLDER/${POSTGRES_HOST}/g" "${SCRIPT_DIR}/deployment.yaml" > "$TMP_DEPLOY"

# Apply resources
kubectl apply -f pvc.yaml
kubectl apply -f "$TMP_DEPLOY"
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml

echo "Waiting for n8n to be ready..."
kubectl wait --namespace n8n \
  --for=condition=ready pod \
  --selector=app=n8n \
  --timeout=300s || echo "n8n may take a while to start on first run"

echo "n8n deployed!"
echo ""
echo "Access URL: https://n8n.apps.house.simonellistonball.com"
