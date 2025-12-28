#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source config.env if available (for Harbor credentials)
HOMELAB_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "${HOMELAB_DIR}/config.env" ]; then
    source "${HOMELAB_DIR}/config.env"
fi

# Configuration
REGISTRY="${REGISTRY:-harbor.apps.house.simonellistonball.com}"
PUSH_USER="${HARBOR_PUSH_USER:-}"
PUSH_PASSWORD="${HARBOR_PUSH_PASSWORD:-}"
IMAGE_NAME="${IMAGE_NAME:-library/webhook-relay}"
TAG="${TAG:-latest}"
SSH_HOST="${SSH_HOST:-k8s}"  # Uses ~/.ssh/config
BUILD_LOCAL="${BUILD_LOCAL:-}"

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "============================================"
echo "  Building webhook-relay"
echo "============================================"
echo ""
echo "Image:  ${FULL_IMAGE}"
echo ""

# Check if we should build locally
ARCH=$(uname -m)
if [ -n "$BUILD_LOCAL" ] || [ "$ARCH" = "x86_64" ]; then
    echo "Building locally..."
    docker build -t "${FULL_IMAGE}" .

    echo ""
    read -p "Push to registry? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker push "${FULL_IMAGE}"
    fi
else
    echo "Building on remote host (${SSH_HOST})..."
    echo ""

    # Test SSH connection
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${SSH_HOST}" "echo ok" &>/dev/null; then
        echo "ERROR: Cannot connect via 'ssh ${SSH_HOST}'"
        echo ""
        echo "Make sure your ~/.ssh/config has the ${SSH_HOST} host configured."
        echo "Or set SSH_HOST to a different host alias."
        echo ""
        echo "Or set BUILD_LOCAL=1 to build locally (requires x86_64)"
        exit 1
    fi

    # Create temp directory on remote
    echo "Creating remote build directory..."
    REMOTE_DIR=$(ssh "${SSH_HOST}" "mktemp -d")

    # Copy source files
    echo "Copying source files to ${SSH_HOST}:${REMOTE_DIR}..."
    rsync -avz --progress \
        --exclude 'target' \
        --exclude '.git' \
        --exclude '*.md' \
        . "${SSH_HOST}:${REMOTE_DIR}/"

    # Build on remote using nerdctl (containerd) with k3s socket
    echo ""
    echo "Building Docker image on remote..."
    ssh "${SSH_HOST}" "cd ${REMOTE_DIR} && sudo nerdctl --address /run/k3s/containerd/containerd.sock build -t ${FULL_IMAGE} ."

    # Import to k8s.io namespace so k3s can use it locally
    echo ""
    echo "Importing image to k8s.io namespace..."
    ssh "${SSH_HOST}" "sudo nerdctl --address /run/k3s/containerd/containerd.sock save ${FULL_IMAGE} | sudo ctr --address /run/k3s/containerd/containerd.sock -n k8s.io images import -"

    # Push to registry (unless SKIP_PUSH is set)
    if [ -n "${SKIP_PUSH}" ]; then
        echo ""
        echo "Skipping push to registry (SKIP_PUSH=1)"
        echo "Image is available locally on ${SSH_HOST}"
    else
        if [ -z "${PUSH_USER}" ] || [ -z "${PUSH_PASSWORD}" ]; then
            echo ""
            echo "WARNING: HARBOR_PUSH_USER or HARBOR_PUSH_PASSWORD not set in config.env"
            echo "Skipping push to registry. Image is available locally."
        else
            echo ""
            echo "Logging in to registry..."
            ssh "${SSH_HOST}" "echo '${PUSH_PASSWORD}' | sudo nerdctl --address /run/k3s/containerd/containerd.sock login ${REGISTRY} -u '${PUSH_USER}' --password-stdin --insecure-registry"

            echo ""
            echo "Pushing to registry..."
            if ! ssh "${SSH_HOST}" "sudo nerdctl --address /run/k3s/containerd/containerd.sock push --insecure-registry ${FULL_IMAGE}"; then
                echo ""
                echo "WARNING: Push failed. The image is still available locally on ${SSH_HOST}."
            fi
        fi
    fi

    # Cleanup
    echo ""
    echo "Cleaning up remote build directory..."
    ssh "${SSH_HOST}" "rm -rf ${REMOTE_DIR}"
fi

echo ""
echo "============================================"
echo "  Build Complete"
echo "============================================"
echo ""
echo "Image: ${FULL_IMAGE}"
echo ""
echo "To deploy:"
echo "  ./15-webhook-relay/deploy.sh"
