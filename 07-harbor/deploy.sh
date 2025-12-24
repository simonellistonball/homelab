#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Installing Harbor..."

# Add Harbor Helm repo
helm repo add harbor https://helm.goharbor.io
helm repo update

# Create namespace
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -

# Create certificate first
kubectl apply -f certificate.yaml

# Wait for certificate to be ready
echo "Waiting for certificate to be ready..."
kubectl wait --for=condition=Ready certificate/harbor-cert -n harbor --timeout=120s

# Substitute passwords in values.yaml
cat values.yaml | \
  sed "s/HARBOR_ADMIN_PASSWORD_PLACEHOLDER/${HARBOR_ADMIN_PASSWORD}/g" | \
  sed "s/POSTGRES_HARBOR_PASSWORD_PLACEHOLDER/${POSTGRES_HARBOR_PASSWORD}/g" | \
  sed "s/POSTGRES_HOST_PLACEHOLDER/${POSTGRES_HOST}/g" \
  > /tmp/harbor-values.yaml

# Install Harbor
helm upgrade --install harbor harbor/harbor \
  --namespace harbor \
  -f /tmp/harbor-values.yaml \
  --wait --timeout 10m

rm /tmp/harbor-values.yaml

kubectl apply -f ingressroute.yaml

echo "Harbor installed!"
echo ""
echo "Access URL: https://harbor.apps.house.simonellistonball.com"
echo "Username: admin"
echo "Password: (from config.env HARBOR_ADMIN_PASSWORD)"
