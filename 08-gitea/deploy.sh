#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

# Use Redis DNS name for service discovery
REDIS_HOST="redis.redis.svc.cluster.local"

echo "Installing Gitea..."

# Add Gitea Helm repo
helm repo add gitea-charts https://dl.gitea.com/charts/
helm repo update

# Create certificate first
kubectl apply -f certificate.yaml

echo "Waiting for certificate to be ready..."
sleep 10

# Install Gitea with Redis IP substituted
cat values.yaml | \
  sed "s/REDIS_PASSWORD_PLACEHOLDER/${REDIS_PASSWORD}/g" | \
  sed "s/REDIS_HOST_PLACEHOLDER/${REDIS_HOST}/g" | \
  sed "s/POSTGRES_GITEA_PASSWORD_PLACEHOLDER/${POSTGRES_GITEA_PASSWORD}/g" | \
  sed "s/POSTGRES_HOST_PLACEHOLDER/${POSTGRES_HOST}/g" | \
  sed "s/GITEA_SSH_IP_PLACEHOLDER/${GITEA_SSH_IP}/g" | \
  sed "s/GITEA_ADMIN_PASSWORD_PLACEHOLDER/${GITEA_ADMIN_PASSWORD}/g" \
  > /tmp/gitea-values.yaml

helm upgrade --install gitea gitea-charts/gitea \
  --namespace gitea \
  --create-namespace \
  -f /tmp/gitea-values.yaml \
  --wait --timeout 10m

rm /tmp/gitea-values.yaml

kubectl apply -f ingressroute.yaml

echo "Gitea installed!"
echo ""
echo "Access URL: https://gitea.apps.house.simonellistonball.com"
echo "SSH: git@gitea.apps.house.simonellistonball.com (port 22 on ${GITEA_SSH_IP})"
