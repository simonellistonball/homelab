#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Installing MetalLB..."

# Install MetalLB using manifest
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

echo "Waiting for MetalLB controller to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s || true

# Wait a bit for CRDs to be registered
sleep 10

echo "Configuring MetalLB IP pool..."
kubectl apply -f ip-pool.yaml
kubectl apply -f l2-advertisement.yaml

echo "MetalLB installed and configured!"
