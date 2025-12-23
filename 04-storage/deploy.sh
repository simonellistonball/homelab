#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Configuring local-path provisioners for multiple drives..."

# Deploy additional local-path provisioners for nvme-fast and scratch
kubectl apply -f local-path-config.yaml

echo "Waiting for provisioners to be ready..."
kubectl -n kube-system wait --for=condition=available deployment/local-path-provisioner-nvme --timeout=60s || true
kubectl -n kube-system wait --for=condition=available deployment/local-path-provisioner-scratch --timeout=60s || true

echo "Installing NFS CSI Driver..."

# Add NFS CSI Driver Helm repo
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

# Install NFS CSI Driver
helm upgrade --install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set driver.name=nfs.csi.k8s.io \
  --wait

echo "Creating NFS storage classes..."
# Substitute config values
TMP_SC=$(mktemp)
TMP_PV=$(mktemp)
trap "rm -f $TMP_SC $TMP_PV" EXIT

sed "s/TRUENAS_IP_PLACEHOLDER/${TRUENAS_IP}/g" "${SCRIPT_DIR}/storage-classes.yaml" > "$TMP_SC"
sed "s/TRUENAS_IP_PLACEHOLDER/${TRUENAS_IP}/g" "${SCRIPT_DIR}/persistent-volumes.yaml" > "$TMP_PV"

kubectl apply -f "$TMP_SC"

echo "Creating persistent volumes..."
kubectl apply -f "$TMP_PV"

echo "Storage configuration complete!"
echo ""
echo "Available storage classes:"
kubectl get storageclasses
