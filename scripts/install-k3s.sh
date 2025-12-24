#!/bin/bash
#
# Install K3s with dual-stack IPv4/IPv6 support for Cilium CNI
#
# This script installs K3s with:
#   - Flannel disabled (Cilium will be used instead)
#   - Built-in servicelb disabled (Cilium L2 will handle LoadBalancers)
#   - Built-in Traefik disabled (we deploy our own)
#   - Dual-stack networking enabled
#
# Prerequisites:
#   - Ubuntu/Debian or similar Linux distribution
#   - Root or sudo access
#   - Network interfaces configured with IPv4 and IPv6
#
# Usage:
#   ./install-k3s.sh
#
# After installation:
#   1. Copy kubeconfig: sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
#   2. Deploy Cilium and other services: ./deploy.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config if available
if [ -f "${SCRIPT_DIR}/../config.env" ]; then
    source "${SCRIPT_DIR}/../config.env"
    echo "Loaded configuration from config.env"
else
    echo "WARNING: config.env not found, using defaults"
fi

# Default CIDRs (can be overridden by config.env)
POD_CIDR_V4="${POD_CIDR_V4:-10.42.0.0/16}"
POD_CIDR_V6="${POD_CIDR_V6:-fd00:10:42::/56}"
SERVICE_CIDR_V4="${SERVICE_CIDR_V4:-10.43.0.0/16}"
SERVICE_CIDR_V6="${SERVICE_CIDR_V6:-fd00:10:43::/112}"

echo "============================================"
echo "  K3s Dual-Stack Installation"
echo "============================================"
echo ""
echo "Configuration:"
echo "  Pod CIDR (IPv4):     ${POD_CIDR_V4}"
echo "  Pod CIDR (IPv6):     ${POD_CIDR_V6}"
echo "  Service CIDR (IPv4): ${SERVICE_CIDR_V4}"
echo "  Service CIDR (IPv6): ${SERVICE_CIDR_V6}"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root or with sudo"
    exit 1
fi

# Check for existing K3s installation
if command -v k3s &> /dev/null; then
    echo "WARNING: K3s is already installed!"
    echo "To reinstall, first run: /usr/local/bin/k3s-uninstall.sh"
    exit 1
fi

# Enable IPv6 forwarding and accept RA (needed for dual-stack)
echo "Configuring sysctl for IPv6..."
cat > /etc/sysctl.d/99-k3s-ipv6.conf << EOF
# K3s dual-stack IPv6 settings
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv4.ip_forward=1
EOF
sysctl --system

# Install K3s with dual-stack configuration
echo ""
echo "Installing K3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
  --flannel-backend=none \
  --disable-network-policy \
  --disable=servicelb \
  --disable=traefik \
  --write-kubeconfig-mode=644 \
  --cluster-cidr=${POD_CIDR_V4},${POD_CIDR_V6} \
  --service-cidr=${SERVICE_CIDR_V4},${SERVICE_CIDR_V6} \
  --kubelet-arg=node-ip=0.0.0.0" sh -

# Wait for K3s to start
echo ""
echo "Waiting for K3s to start..."
sleep 10

# Check K3s status
if systemctl is-active --quiet k3s; then
    echo "K3s is running!"
else
    echo "ERROR: K3s failed to start"
    journalctl -u k3s --no-pager -n 50
    exit 1
fi

# Set up kubeconfig for current user
SUDO_USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
if [ -n "$SUDO_USER_HOME" ] && [ "$SUDO_USER_HOME" != "/root" ]; then
    echo ""
    echo "Setting up kubeconfig for ${SUDO_USER:-$USER}..."
    mkdir -p "${SUDO_USER_HOME}/.kube"
    cp /etc/rancher/k3s/k3s.yaml "${SUDO_USER_HOME}/.kube/config"
    chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "${SUDO_USER_HOME}/.kube"
    chmod 600 "${SUDO_USER_HOME}/.kube/config"

    # Add KUBECONFIG to user's profile if not already present
    PROFILE_FILE="${SUDO_USER_HOME}/.bashrc"
    if ! grep -q 'export KUBECONFIG=' "$PROFILE_FILE" 2>/dev/null; then
        echo "" >> "$PROFILE_FILE"
        echo '# Kubernetes config' >> "$PROFILE_FILE"
        echo 'export KUBECONFIG="$HOME/.kube/config"' >> "$PROFILE_FILE"
        chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$PROFILE_FILE"
        echo "Added KUBECONFIG to ${PROFILE_FILE}"
    fi
fi

echo ""
echo "============================================"
echo "  K3s Installation Complete!"
echo "============================================"
echo ""
echo "Kubeconfig: /etc/rancher/k3s/k3s.yaml"
echo ""
echo "Next steps:"
echo "  1. Verify cluster: kubectl get nodes"
echo "  2. Deploy Cilium and services: ./deploy.sh"
echo ""
echo "NOTE: Pods will be in Pending state until Cilium CNI is deployed!"
echo ""
