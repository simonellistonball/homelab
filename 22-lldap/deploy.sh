#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Installing LLDAP..."

# Create auth namespace (shared with Authentik)
kubectl create namespace auth --dry-run=client -o yaml | kubectl apply -f -

# Substitute environment variables and apply
for file in secret.yaml certificate.yaml deployment.yaml service.yaml ingressroute.yaml; do
    echo "Applying ${file}..."
    envsubst < "${SCRIPT_DIR}/${file}" | kubectl apply -f -
done

# Wait for LLDAP to be ready
echo "Waiting for LLDAP to be ready..."
kubectl wait --namespace auth \
  --for=condition=ready pod \
  --selector=app=lldap \
  --timeout=120s

echo ""
echo "=========================================="
echo "LLDAP installed!"
echo "=========================================="
echo ""
echo "Web UI: https://ldap.${DOMAIN}/"
echo "Admin user: admin"
echo "Admin password: (from LLDAP_ADMIN_PASSWORD in config.env)"
echo ""
echo "LDAPS Connection Info (TLS secured):"
echo "  URI: ldaps://lldap.auth.svc.cluster.local:636"
echo "  Base DN: dc=house,dc=simonellistonball,dc=com"
echo "  Bind DN: uid=admin,ou=people,dc=house,dc=simonellistonball,dc=com"
echo "  CA: Use Simon Elliston Ball Root CA (trust bundle)"
echo ""
echo "Plain LDAP (internal only, not recommended):"
echo "  URI: ldap://lldap.auth.svc.cluster.local:389"
echo ""
echo "Next steps:"
echo "  1. Log in to https://ldap.${DOMAIN}/"
echo "  2. Create groups: media, backup, family, admins"
echo "  3. Create users with appropriate UID/GID"
echo "  4. Configure TrueNAS Directory Services to use LDAPS"
echo "  5. Configure Authentik LDAP source to sync users"
echo ""
echo "NOTE: TrueNAS needs the Root CA certificate for LDAPS verification."
echo "      Export from: 03-cert-manager/root-ca-configmap.yaml"
echo ""
