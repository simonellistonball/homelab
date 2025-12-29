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

# Wait for certificate to be ready
echo "Waiting for certificate to be ready..."
kubectl wait --for=condition=Ready certificate/dagster-cert -n dagster --timeout=120s

# Substitute passwords in values.yaml
cat values.yaml | \
  sed "s/POSTGRES_DAGSTER_PASSWORD_PLACEHOLDER/${POSTGRES_DAGSTER_PASSWORD}/g" | \
  sed "s/POSTGRES_HOST_PLACEHOLDER/${POSTGRES_HOST}/g" \
  > /tmp/dagster-values.yaml

# Install Dagster
# Note: --skip-schema-validation is needed because the chart's values.schema.json
# references kubernetesjsonschema.dev which has been deprecated and returns 404
helm upgrade --install dagster dagster/dagster \
  --namespace dagster \
  -f /tmp/dagster-values.yaml \
  --skip-schema-validation \
  --wait --timeout 10m

rm /tmp/dagster-values.yaml

kubectl apply -f ingressroute.yaml

echo "Dagster installed!"
echo ""
echo "Access URL: https://dagster.apps.house.simonellistonball.com"
