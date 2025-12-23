#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

# Local storage mount points (should be mounted on the K3s node)
NVME_FAST_PATH="${NVME_FAST_PATH:-/mnt/nvme-fast}"
SCRATCH_PATH="${SCRATCH_PATH:-/mnt/scratch}"

echo "============================================"
echo "  Storage Configuration"
echo "============================================"
echo ""

# Test that local mount points exist on the node
echo "Checking local storage mount points on K3s node..."
check_mount() {
    local path="$1"
    local name="$2"
    if kubectl run mount-check-$$  --rm -i --restart=Never --image=busybox -- test -d "$path" 2>/dev/null; then
        echo "  ✓ $name ($path) exists"
        return 0
    else
        echo "  ✗ $name ($path) NOT FOUND"
        echo "    Run on K3s node: sudo mkdir -p $path && sudo chmod 777 $path"
        return 1
    fi
}

MOUNT_OK=true
check_mount "$NVME_FAST_PATH" "nvme-fast" || MOUNT_OK=false
check_mount "$SCRATCH_PATH" "scratch" || MOUNT_OK=false

if [ "$MOUNT_OK" = false ]; then
    echo ""
    echo "WARNING: Some mount points are missing. Local storage classes may not work."
    echo "Continue anyway? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo ""
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

# Test storage classes
echo ""
echo "Testing storage classes..."

test_storage_class() {
    local sc="$1"
    local ns="default"
    local pvc_name="test-${sc}-$$"

    echo -n "  Testing $sc... "

    # Create test PVC
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: ${ns}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${sc}
  resources:
    requests:
      storage: 1Mi
EOF

    # Wait briefly for binding (local-path binds on first consumer, so just check it was created)
    sleep 2
    if kubectl get pvc ${pvc_name} -n ${ns} >/dev/null 2>&1; then
        echo "✓ PVC created"
        kubectl delete pvc ${pvc_name} -n ${ns} >/dev/null 2>&1 || true
    else
        echo "✗ Failed"
    fi
}

test_storage_class "nvme-fast"
test_storage_class "scratch"

echo ""
echo "Storage setup complete!"
