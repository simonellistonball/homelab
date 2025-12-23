#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Installing cert-manager..."

# Add Jetstack Helm repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager with CRDs
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set prometheus.enabled=true \
  --wait

echo "Waiting for cert-manager to be ready..."
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s

echo "Installing CA secret..."
kubectl apply -f ca-secret.yaml

echo "Creating ClusterIssuer..."
kubectl apply -f cluster-issuer.yaml

echo "Creating wildcard certificate..."
kubectl apply -f wildcard-certificate.yaml

echo "cert-manager installed with private CA!"
