#!/bin/bash
#
# Deploy Cilium CNI for K3s with IPv6 dual-stack support and L2 load balancing
#
# IMPORTANT: K3s must be installed with Flannel disabled:
#   curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend=none --disable-network-policy --disable=servicelb --disable=traefik" sh -
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

NAMESPACE="kube-system"
CILIUM_VERSION="1.19.0-pre.3"

echo "============================================"
echo "  Deploying Cilium CNI v${CILIUM_VERSION}"
echo "============================================"
echo ""

# Check if Cilium CLI is installed
install_cilium_cli() {
    echo "Installing Cilium CLI..."
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)

    # Detect architecture
    CLI_ARCH=amd64
    if [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
        CLI_ARCH=arm64
    fi

    # Detect OS
    case "$(uname -s)" in
        Linux*)  CLI_OS=linux ;;
        Darwin*) CLI_OS=darwin ;;
        *)       echo "Unsupported OS"; exit 1 ;;
    esac

    curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-${CLI_OS}-${CLI_ARCH}.tar.gz{,.sha256sum}"
    sha256sum --check "cilium-${CLI_OS}-${CLI_ARCH}.tar.gz.sha256sum" || shasum -a 256 --check "cilium-${CLI_OS}-${CLI_ARCH}.tar.gz.sha256sum"
    sudo tar xzvfC "cilium-${CLI_OS}-${CLI_ARCH}.tar.gz" /usr/local/bin
    rm -f "cilium-${CLI_OS}-${CLI_ARCH}.tar.gz" "cilium-${CLI_OS}-${CLI_ARCH}.tar.gz.sha256sum"
    echo "Cilium CLI installed successfully"
}

if ! command -v cilium &> /dev/null; then
    install_cilium_cli
fi

# Add Cilium Helm repo
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium

# Create temporary values file with substitutions
TMP_VALUES=$(mktemp)
trap "rm -f $TMP_VALUES" EXIT

# Default pod CIDRs if not set
POD_CIDR_V4="${POD_CIDR_V4:-10.42.0.0/16}"
POD_CIDR_V6="${POD_CIDR_V6:-fd00:10:42::/48}"

sed -e "s/K8S_NODE_IP_PLACEHOLDER/${K8S_NODE_IP}/g" \
    -e "s|POD_CIDR_V4_PLACEHOLDER|${POD_CIDR_V4}|g" \
    -e "s|POD_CIDR_V6_PLACEHOLDER|${POD_CIDR_V6}|g" \
    "${SCRIPT_DIR}/values.yaml" > "$TMP_VALUES"

# Check if Cilium is already installed
if helm status cilium -n ${NAMESPACE} &>/dev/null; then
    echo "Upgrading Cilium to v${CILIUM_VERSION}..."
    helm upgrade cilium cilium/cilium \
        --namespace ${NAMESPACE} \
        --version ${CILIUM_VERSION} \
        --values "$TMP_VALUES" \
        --wait
else
    echo "Installing Cilium v${CILIUM_VERSION}..."
    helm install cilium cilium/cilium \
        --namespace ${NAMESPACE} \
        --version ${CILIUM_VERSION} \
        --values "$TMP_VALUES" \
        --wait
fi

echo ""
echo "Waiting for Cilium to be ready..."
sleep 5
cilium status --wait || true

# Apply L2 Load Balancer configuration
echo ""
echo "Configuring L2 Load Balancer..."

# Create temporary manifests with substitutions
TMP_IP_POOL=$(mktemp)
TMP_L2_ANNOUNCE=$(mktemp)
trap "rm -f $TMP_VALUES $TMP_IP_POOL $TMP_L2_ANNOUNCE" EXIT

# Default LB pools if not set
CILIUM_LB_POOL_V4="${CILIUM_LB_POOL_V4:-192.168.100.100/25}"
CILIUM_LB_POOL_V6="${CILIUM_LB_POOL_V6:-2a0e:cb01:f1:1001::/64}"

# Default Traefik IPs (pick first usable from each pool if not set)
TRAEFIK_IP="${TRAEFIK_IP:-192.168.100.111}"
TRAEFIK_IP_V6="${TRAEFIK_IP_V6:-2a0e:cb01:f1:1001::1}"

sed -e "s|CILIUM_LB_POOL_V4_PLACEHOLDER|${CILIUM_LB_POOL_V4}|g" \
    -e "s|CILIUM_LB_POOL_V6_PLACEHOLDER|${CILIUM_LB_POOL_V6}|g" \
    -e "s|TRAEFIK_IP_PLACEHOLDER|${TRAEFIK_IP}|g" \
    -e "s|TRAEFIK_IP_V6_PLACEHOLDER|${TRAEFIK_IP_V6}|g" \
    "${SCRIPT_DIR}/ip-pool.yaml" > "$TMP_IP_POOL"

cp "${SCRIPT_DIR}/l2-announcement.yaml" "$TMP_L2_ANNOUNCE"

# Apply L2 configuration
kubectl apply -f "$TMP_IP_POOL"
kubectl apply -f "$TMP_L2_ANNOUNCE"

echo ""
echo "============================================"
echo "  Cilium deployed successfully!"
echo "============================================"
echo ""
echo "Useful commands:"
echo "  cilium status              - Check Cilium status"
echo "  cilium connectivity test   - Run connectivity tests"
echo "  hubble status              - Check Hubble observability status"
echo "  kubectl get ciliuml2announcementpolicies"
echo "  kubectl get ciliumloadbalancerippools"
echo ""
echo "LoadBalancer IP Pools (Dual-Stack):"
echo "  IPv4: ${CILIUM_LB_POOL_V4}"
echo "  IPv6: ${CILIUM_LB_POOL_V6}"
echo ""
echo "Traefik IPs:"
echo "  IPv4: ${TRAEFIK_IP}"
echo "  IPv6: ${TRAEFIK_IP_V6}"
echo ""
