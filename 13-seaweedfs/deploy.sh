#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source environment variables
source ../config.env

echo "=== Deploying SeaweedFS ==="

# Create namespace
echo "Creating namespace..."
kubectl create namespace seaweedfs --dry-run=client -o yaml | kubectl apply -f -

# Create S3 credentials secret
echo "Creating S3 credentials secret..."
kubectl create secret generic seaweedfs-s3-secret \
  --namespace seaweedfs \
  --from-literal=access_key="${SEAWEEDFS_ACCESS_KEY}" \
  --from-literal=secret_key="${SEAWEEDFS_SECRET_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create certificate
echo "Creating certificate..."
kubectl apply -f certificate.yaml

# Wait for certificate to be ready
echo "Waiting for certificate to be ready..."
kubectl wait --for=condition=Ready certificate/seaweedfs-cert -n seaweedfs --timeout=120s

# Create ConfigMaps with substituted credentials
echo "Creating ConfigMaps..."
cat configmap.yaml | \
  sed "s/SEAWEEDFS_ACCESS_KEY_PLACEHOLDER/${SEAWEEDFS_ACCESS_KEY}/g" | \
  sed "s/SEAWEEDFS_SECRET_KEY_PLACEHOLDER/${SEAWEEDFS_SECRET_KEY}/g" | \
  sed "s/SEAWEEDFS_READONLY_ACCESS_KEY_PLACEHOLDER/${SEAWEEDFS_READONLY_ACCESS_KEY}/g" | \
  sed "s/SEAWEEDFS_READONLY_SECRET_KEY_PLACEHOLDER/${SEAWEEDFS_READONLY_SECRET_KEY}/g" | \
  kubectl apply -f -

# Create PVCs
echo "Creating persistent volume claims..."
kubectl apply -f pvc.yaml

# Deploy Master
echo "Deploying SeaweedFS Master..."
kubectl apply -f master.yaml

# Wait for master to be ready
echo "Waiting for master to be ready..."
kubectl wait --for=condition=ready pod -l app=seaweedfs-master -n seaweedfs --timeout=180s

# Deploy Volume Servers (all tiers)
echo "Deploying SeaweedFS Volume Servers (hot/warm/cold tiers)..."
kubectl apply -f volume.yaml

# Wait for volume servers to be ready
echo "Waiting for volume servers to be ready..."
kubectl wait --for=condition=ready pod -l app=seaweedfs-volume-hot -n seaweedfs --timeout=180s
kubectl wait --for=condition=ready pod -l app=seaweedfs-volume-warm -n seaweedfs --timeout=180s
kubectl wait --for=condition=ready pod -l app=seaweedfs-volume-cold -n seaweedfs --timeout=180s

# Deploy Filer with S3 API
echo "Deploying SeaweedFS Filer with S3 API..."
kubectl apply -f filer.yaml

# Wait for filer to be ready
echo "Waiting for filer to be ready..."
kubectl wait --for=condition=ready pod -l app=seaweedfs-filer -n seaweedfs --timeout=180s

# Apply ingress routes
echo "Configuring ingress..."
kubectl apply -f ingressroute.yaml

echo ""
echo "=== SeaweedFS Deployment Complete ==="
echo ""
echo "S3 API Endpoint: https://s3.apps.house.simonellistonball.com"
echo "Filer Web UI:    https://seaweedfs.apps.house.simonellistonball.com"
echo ""
echo "S3 Credentials:"
echo "  Access Key: ${SEAWEEDFS_ACCESS_KEY}"
echo "  Secret Key: ${SEAWEEDFS_SECRET_KEY}"
echo ""
echo "Storage Tiers:"
echo "  Hot (ssd):  NVMe storage for frequently accessed data"
echo "  Warm (hdd): NFS storage for regular data"
echo "  Cold (hdd): NFS archive for infrequently accessed data"
echo ""
echo "Bucket Tiering (path-based):"
echo "  /buckets/hot/*     -> Hot tier (SSD)"
echo "  /buckets/cache/*   -> Hot tier (SSD)"
echo "  /buckets/data/*    -> Warm tier (HDD)"
echo "  /buckets/archive/* -> Cold tier (HDD)"
echo "  /buckets/backup/*  -> Cold tier (HDD)"
echo ""
echo "Example AWS CLI usage:"
echo "  export AWS_ACCESS_KEY_ID=${SEAWEEDFS_ACCESS_KEY}"
echo "  export AWS_SECRET_ACCESS_KEY=${SEAWEEDFS_SECRET_KEY}"
echo "  aws --endpoint-url=https://s3.apps.house.simonellistonball.com s3 mb s3://mybucket"
echo "  aws --endpoint-url=https://s3.apps.house.simonellistonball.com s3 cp file.txt s3://mybucket/"
