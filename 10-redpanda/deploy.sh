#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Installing Redpanda..."

# Add Redpanda Helm repo
helm repo add redpanda https://charts.redpanda.com
helm repo update

# Create certificates first
kubectl apply -f certificates.yaml

# Wait for certificates to be ready
echo "Waiting for certificates to be ready..."
kubectl wait --for=condition=Ready certificate/redpanda-internal-cert -n redpanda --timeout=120s
kubectl wait --for=condition=Ready certificate/redpanda-external-cert -n redpanda --timeout=120s 2>/dev/null || true

# Install Redpanda
helm upgrade --install redpanda redpanda/redpanda \
  --namespace redpanda \
  --create-namespace \
  -f values.yaml \
  --wait --timeout 10m

kubectl apply -f ingressroute.yaml

echo "Redpanda installed!"
echo ""
echo "Console URL: https://redpanda.apps.house.simonellistonball.com"
echo ""
echo "Kafka Bootstrap: redpanda.redpanda.svc.cluster.local:9093"
