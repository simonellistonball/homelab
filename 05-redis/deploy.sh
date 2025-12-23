#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Deploying Redis..."

# Create secret with password
kubectl create namespace redis --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic redis-secret \
  --namespace redis \
  --from-literal=password="${REDIS_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

echo "Waiting for Redis to be ready..."
kubectl wait --namespace redis \
  --for=condition=ready pod \
  --selector=app=redis \
  --timeout=120s

echo "Redis deployed!"
echo "Redis Service IP: $(kubectl get svc redis -n redis -o jsonpath='{.spec.clusterIP}')"
