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

# Create serendipity postgres secret
echo "Creating serendipity postgres secret..."
kubectl create secret generic serendipity-postgres-secret \
  --namespace dagster \
  --from-literal=POSTGRES_HOST="${POSTGRES_HOST}" \
  --from-literal=POSTGRES_PORT="${POSTGRES_PORT}" \
  --from-literal=POSTGRES_USER="serendipity" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_SERENDIPITY_PASSWORD}" \
  --from-literal=POSTGRES_DB="serendipity" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create serendipity storage config
echo "Creating serendipity storage configmap..."
kubectl create configmap serendipity-storage-config \
  --namespace dagster \
  --from-literal=NFS_SERVER="truenas.house.simonellistonball.com" \
  --from-literal=NFS_PATH="/mnt/data/data" \
  --from-literal=OPENALEX_DATA_DIR="/mnt/data/data/openalex" \
  --dry-run=client -o yaml | kubectl apply -f -

# Substitute passwords and config in values.yaml
cat values.yaml | \
  sed "s/POSTGRES_DAGSTER_PASSWORD_PLACEHOLDER/${POSTGRES_DAGSTER_PASSWORD}/g" | \
  sed "s/POSTGRES_HOST_PLACEHOLDER/${POSTGRES_HOST}/g" | \
  sed "s/TRUENAS_IP_PLACEHOLDER/${TRUENAS_IP}/g" \
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
