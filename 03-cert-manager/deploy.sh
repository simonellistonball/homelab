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

echo "Installing trust-manager..."
helm upgrade --install trust-manager jetstack/trust-manager \
  --namespace cert-manager \
  --set app.trust.namespace=cert-manager \
  --wait

echo "Waiting for trust-manager to be ready..."
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=trust-manager \
  --timeout=120s

echo "Installing CA secret..."
kubectl apply -f ca-secret.yaml

echo "Installing root CA ConfigMap for trust distribution..."
kubectl apply -f root-ca-configmap.yaml

echo "Creating ClusterIssuer..."
kubectl apply -f cluster-issuer.yaml

echo "Creating trust bundle for CA distribution..."
kubectl apply -f trust-bundle.yaml

echo "Creating wildcard certificate..."
kubectl apply -f wildcard-certificate.yaml

echo "Creating external service certificates..."
kubectl apply -f external-certificates.yaml

# Wait for certificates to be issued
echo "Waiting for certificates to be ready..."
for cert in nas-cert postgres-cert homeassistant-cert pi5-cert unifi-cert; do
    echo -n "  Waiting for $cert... "
    kubectl wait --for=condition=Ready certificate/$cert -n cert-manager --timeout=60s >/dev/null 2>&1 && echo "ready" || echo "timeout (may already exist)"
done

# Export certificates for external use
EXPORT_DIR="${SCRIPT_DIR}/exported-certs"
mkdir -p "$EXPORT_DIR"

echo ""
echo "Exporting certificates to $EXPORT_DIR..."

# Export CA certificate (needed for trusting on external systems)
echo "  Exporting CA certificate..."
kubectl get secret ca-key-pair -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > "$EXPORT_DIR/ca.crt"

# Export each external certificate
export_cert() {
    local name="$1"
    local secret="$2"
    echo "  Exporting $name..."
    kubectl get secret "$secret" -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > "$EXPORT_DIR/${name}.crt"
    kubectl get secret "$secret" -n cert-manager -o jsonpath='{.data.tls\.key}' | base64 -d > "$EXPORT_DIR/${name}.key"
    chmod 600 "$EXPORT_DIR/${name}.key"
}

export_cert "nas" "nas-tls"
export_cert "postgres" "postgres-tls"
export_cert "homeassistant" "homeassistant-tls"
export_cert "pi5" "pi5-tls"
export_cert "unifi" "unifi-tls"

echo ""
echo "cert-manager installed with private CA!"
echo ""
echo "Exported certificates are in: $EXPORT_DIR"
echo "  - ca.crt                 : CA certificate (install on clients to trust)"
echo "  - nas.crt, nas.key       : TrueNAS"
echo "  - postgres.crt, postgres.key : PostgreSQL"
echo "  - homeassistant.crt, homeassistant.key : Home Assistant"
echo "  - pi5.crt, pi5.key       : Pi5 K3s node"
echo "  - unifi.crt, unifi.key   : UniFi UDM"
echo ""
echo "NOTE: Keep these files secure! The .key files contain private keys."
