#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Deploying AI services (LiteLLM + Whisper)..."

# Create namespaces
kubectl create namespace ai --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace whisper --dry-run=client -o yaml | kubectl apply -f -

# Create certificates
kubectl apply -f litellm/certificate.yaml
kubectl apply -f whisper/certificate.yaml

# Deploy LiteLLM
echo "Deploying LiteLLM..."

# Create LiteLLM secrets
kubectl create secret generic litellm-secrets \
  --namespace ai \
  --from-literal=LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}" \
  --from-literal=LITELLM_SALT_KEY="${LITELLM_SALT_KEY}" \
  --from-literal=DATABASE_URL="postgresql://litellm:${POSTGRES_LITELLM_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/litellm" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f litellm/configmap.yaml
kubectl apply -f litellm/deployment.yaml
kubectl apply -f litellm/service.yaml
kubectl apply -f litellm/ingressroute.yaml
kubectl apply -f litellm/servicemonitor.yaml

# Deploy Whisper
echo "Deploying Whisper..."

# Create Harbor pull secret if it doesn't exist
kubectl create secret docker-registry harbor-pull \
  --namespace whisper \
  --docker-server=harbor.apps.house.simonellistonball.com \
  --docker-username=admin \
  --docker-password="${HARBOR_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f whisper/pvc.yaml
kubectl apply -f whisper/deployment.yaml
kubectl apply -f whisper/service.yaml
kubectl apply -f whisper/ingressroute.yaml

echo "Waiting for LiteLLM to be ready..."
kubectl wait --namespace ai \
  --for=condition=ready pod \
  --selector=app=litellm \
  --timeout=300s || echo "LiteLLM may take a while to start"

echo "AI services deployed!"
echo ""
echo "LiteLLM URL: https://llm.apps.house.simonellistonball.com"
echo "Whisper URL: https://whisper.apps.house.simonellistonball.com"
