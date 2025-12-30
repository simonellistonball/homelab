#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Installing Authentik..."

# Create namespace (shared with LLDAP)
kubectl create namespace auth --dry-run=client -o yaml | kubectl apply -f -

# Add Authentik Helm repo
helm repo add goauthentik https://charts.goauthentik.io
helm repo update

# Create PostgreSQL database if it doesn't exist
echo "Ensuring PostgreSQL database exists..."
PGPASSWORD="${POSTGRES_AUTHENTIK_PASSWORD}" psql -h "${POSTGRES_HOST}" -U postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname = 'authentik'" | grep -q 1 || \
PGPASSWORD="${POSTGRES_AUTHENTIK_PASSWORD}" psql -h "${POSTGRES_HOST}" -U postgres -c \
  "CREATE DATABASE authentik;"

# Create PostgreSQL user if it doesn't exist
PGPASSWORD="${POSTGRES_AUTHENTIK_PASSWORD}" psql -h "${POSTGRES_HOST}" -U postgres -tc \
  "SELECT 1 FROM pg_roles WHERE rolname = 'authentik'" | grep -q 1 || \
PGPASSWORD="${POSTGRES_AUTHENTIK_PASSWORD}" psql -h "${POSTGRES_HOST}" -U postgres -c \
  "CREATE USER authentik WITH PASSWORD '${POSTGRES_AUTHENTIK_PASSWORD}';"

PGPASSWORD="${POSTGRES_AUTHENTIK_PASSWORD}" psql -h "${POSTGRES_HOST}" -U postgres -c \
  "GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;"

# Substitute environment variables in values.yaml
envsubst < "${SCRIPT_DIR}/values.yaml" > /tmp/authentik-values.yaml

# Install Authentik
helm upgrade --install authentik goauthentik/authentik \
  --namespace auth \
  -f /tmp/authentik-values.yaml \
  --wait --timeout 10m

# Clean up temp file
rm -f /tmp/authentik-values.yaml

# Apply certificate, IngressRoute, and middleware
kubectl apply -f "${SCRIPT_DIR}/certificate.yaml"
kubectl apply -f "${SCRIPT_DIR}/ingressroute.yaml"
kubectl apply -f "${SCRIPT_DIR}/middleware.yaml"

# Wait for Authentik to be ready
echo "Waiting for Authentik to be ready..."
kubectl wait --namespace auth \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=authentik \
  --selector=app.kubernetes.io/component=server \
  --timeout=300s

echo ""
echo "=========================================="
echo "Authentik installed!"
echo "=========================================="
echo ""
echo "Access: https://auth.${DOMAIN}/"
echo ""
echo "Initial setup:"
echo "  1. Navigate to https://auth.${DOMAIN}/if/flow/initial-setup/"
echo "  2. Create your admin account (akadmin)"
echo "  3. Configure OIDC applications for your services"
echo ""
echo "For Traefik forward auth, use the embedded outpost or create one:"
echo "  - Go to Applications > Outposts"
echo "  - Create 'traefik' outpost with type 'Proxy'"
echo ""
echo "LLDAP Integration (LDAPS/TLS):"
echo "  If LLDAP is deployed, configure LDAP source in Authentik:"
echo "  - Directory > Federation > Create > LDAP Source"
echo "  - Server URI: ldaps://lldap.auth.svc.cluster.local:636"
echo "  - Base DN: dc=house,dc=simonellistonball,dc=com"
echo "  - TLS secured with Simon Elliston Ball Root CA"
echo "  - See 22-lldap/INTEGRATIONS.md for details"
echo ""
