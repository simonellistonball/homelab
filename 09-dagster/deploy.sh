#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Installing Dagster..."

# Add Dagster Helm repo
helm repo add dagster https://dagster-io.github.io/helm
helm repo update

# Create namespace
kubectl create namespace dagster --dry-run=client -o yaml | kubectl apply -f -

# Create certificate first
kubectl apply -f certificate.yaml

echo "Waiting for certificate to be ready..."
sleep 10

# Substitute passwords in values.yaml
cat values.yaml | \
  sed "s/POSTGRES_DAGSTER_PASSWORD_PLACEHOLDER/${POSTGRES_DAGSTER_PASSWORD}/g" \
  > /tmp/dagster-values.yaml

# Install Dagster
helm upgrade --install dagster dagster/dagster \
  --namespace dagster \
  -f /tmp/dagster-values.yaml \
  --wait --timeout 10m

rm /tmp/dagster-values.yaml

kubectl apply -f ingressroute.yaml

echo "Dagster installed!"
echo ""
echo "Access URL: https://dagster.apps.house.simonellistonball.com"
