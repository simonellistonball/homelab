#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Installing Traefik..."

# Add Traefik Helm repo
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install Traefik
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  -f values.yaml \
  --wait

echo "Waiting for Traefik to get LoadBalancer IP..."
kubectl wait --namespace traefik \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=traefik \
  --timeout=120s

echo "Traefik installed!"
echo "LoadBalancer IP: $(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
