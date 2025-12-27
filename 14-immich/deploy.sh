#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Deploying Immich..."

# Create namespace
kubectl create namespace immich --dry-run=client -o yaml | kubectl apply -f -

# Create certificate first
kubectl apply -f "${SCRIPT_DIR}/certificate.yaml"

# Create secrets
kubectl create secret generic immich-secrets \
  --namespace immich \
  --from-literal=DB_PASSWORD="${POSTGRES_IMMICH_PASSWORD}" \
  --from-literal=REDIS_PASSWORD="${REDIS_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Note: Root CA trust is automatically distributed by trust-manager
# via the simonellistonball-ca-bundle ConfigMap

# Wait for certificate to be ready
echo "Waiting for certificate to be ready..."
kubectl wait --for=condition=Ready certificate/immich-cert -n immich --timeout=120s

# Substitute config values
TMP_DEPLOY=$(mktemp)
TMP_ML=$(mktemp)
trap "rm -f $TMP_DEPLOY $TMP_ML" EXIT

sed -e "s/POSTGRES_HOST_PLACEHOLDER/${POSTGRES_HOST}/g" \
    -e "s/REDIS_HOST_PLACEHOLDER/redis.redis.svc.cluster.local/g" \
    "${SCRIPT_DIR}/deployment.yaml" > "$TMP_DEPLOY"

sed -e "s/POSTGRES_HOST_PLACEHOLDER/${POSTGRES_HOST}/g" \
    -e "s/REDIS_HOST_PLACEHOLDER/redis.redis.svc.cluster.local/g" \
    "${SCRIPT_DIR}/machine-learning.yaml" > "$TMP_ML"

# Apply resources
kubectl apply -f "${SCRIPT_DIR}/pvc.yaml"
kubectl apply -f "$TMP_DEPLOY"
kubectl apply -f "$TMP_ML"
kubectl apply -f "${SCRIPT_DIR}/service.yaml"
kubectl apply -f "${SCRIPT_DIR}/ingressroute.yaml"

echo "Waiting for Immich server to be ready..."
kubectl wait --namespace immich \
  --for=condition=ready pod \
  --selector=app=immich-server \
  --timeout=300s || echo "Immich may take a while to start on first run"

echo ""
echo "Immich deployed!"
echo ""
echo "Access URL: https://immich.apps.house.simonellistonball.com"
echo ""
echo "First time setup:"
echo "  1. Visit the URL above"
echo "  2. Create an admin account"
echo "  3. Configure your photo libraries"
