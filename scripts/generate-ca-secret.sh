#!/bin/bash
#
# Generate Kubernetes TLS secret for cert-manager from a CA structure
#
# Usage: ./scripts/generate-ca-secret.sh [CA_DIR]
#
# Expected CA directory structure:
#   CA_DIR/
#   ├── intermediate/
#   │   ├── certs/
#   │   │   ├── ca-chain.cert.pem      # Full certificate chain (intermediate + root)
#   │   │   └── intermediate.cert.pem   # Intermediate certificate only
#   │   └── private/
#   │       ├── intermediate.key.pem            # Encrypted private key
#   │       └── intermediate.key.decrpyted.pem  # Decrypted private key (used by default)
#   └── simonellistonball-CA.crt                # Root CA certificate
#
# The script will use:
#   - ca-chain.cert.pem for tls.crt (contains intermediate + root for full chain validation)
#   - intermediate.key.decrpyted.pem for tls.key (must be decrypted for Kubernetes)
#
# Output: 03-cert-manager/ca-secret.yaml
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default CA directory
CA_DIR="${1:-${REPO_ROOT}/ca}"

# Output file
OUTPUT_FILE="${REPO_ROOT}/03-cert-manager/ca-secret.yaml"

# Certificate and key paths
CERT_CHAIN="${CA_DIR}/intermediate/certs/ca-chain.cert.pem"
PRIVATE_KEY="${CA_DIR}/intermediate/private/intermediate.key.decrpyted.pem"

# Validate CA directory exists
if [[ ! -d "${CA_DIR}" ]]; then
    echo "Error: CA directory not found: ${CA_DIR}" >&2
    echo "" >&2
    echo "Usage: $0 [CA_DIR]" >&2
    echo "" >&2
    echo "Please provide a path to your CA directory with the following structure:" >&2
    echo "  CA_DIR/" >&2
    echo "  └── intermediate/" >&2
    echo "      ├── certs/" >&2
    echo "      │   └── ca-chain.cert.pem" >&2
    echo "      └── private/" >&2
    echo "          └── intermediate.key.decrpyted.pem" >&2
    exit 1
fi

# Validate certificate chain exists
if [[ ! -f "${CERT_CHAIN}" ]]; then
    echo "Error: Certificate chain not found: ${CERT_CHAIN}" >&2
    echo "Expected: ca-chain.cert.pem containing intermediate + root certificates" >&2
    exit 1
fi

# Validate private key exists
if [[ ! -f "${PRIVATE_KEY}" ]]; then
    echo "Error: Private key not found: ${PRIVATE_KEY}" >&2
    echo "Expected: intermediate.key.decrpyted.pem (decrypted private key)" >&2
    echo "" >&2
    echo "If you only have an encrypted key (intermediate.key.pem), decrypt it with:" >&2
    echo "  openssl rsa -in ${CA_DIR}/intermediate/private/intermediate.key.pem \\" >&2
    echo "              -out ${CA_DIR}/intermediate/private/intermediate.key.decrpyted.pem" >&2
    exit 1
fi

# Verify the certificate and key match
echo "Validating certificate and key pair..."
CERT_MODULUS=$(openssl x509 -noout -modulus -in "${CERT_CHAIN}" 2>/dev/null | head -1 | openssl md5)
KEY_MODULUS=$(openssl rsa -noout -modulus -in "${PRIVATE_KEY}" 2>/dev/null | openssl md5)

if [[ "${CERT_MODULUS}" != "${KEY_MODULUS}" ]]; then
    echo "Error: Certificate and private key do not match!" >&2
    echo "Certificate modulus: ${CERT_MODULUS}" >&2
    echo "Key modulus: ${KEY_MODULUS}" >&2
    exit 1
fi
echo "Certificate and key match."

# Base64 encode the certificate and key
echo "Encoding certificate chain..."
TLS_CRT=$(base64 < "${CERT_CHAIN}" | tr -d '\n')

echo "Encoding private key..."
TLS_KEY=$(base64 < "${PRIVATE_KEY}" | tr -d '\n')

# Generate the secret YAML
echo "Generating secret: ${OUTPUT_FILE}"
cat > "${OUTPUT_FILE}" << EOF
# Private CA Secret
# This contains the intermediate CA certificate and key
# The tls.crt contains the certificate chain (intermediate + root)
# GENERATED FILE - Do not edit manually!
# Regenerate with: ./scripts/generate-ca-secret.sh
apiVersion: v1
kind: Secret
metadata:
  name: intermediate-ca-secret
  namespace: cert-manager
type: kubernetes.io/tls
data:
  # Base64 encoded certificate chain (intermediate + root CA)
  tls.crt: ${TLS_CRT}
  # Base64 encoded private key
  tls.key: ${TLS_KEY}
EOF

echo ""
echo "Successfully generated ${OUTPUT_FILE}"
echo ""
echo "Certificate details:"
openssl x509 -noout -subject -issuer -dates -in "${CERT_CHAIN}" | head -4

echo ""
echo "To apply the secret:"
echo "  kubectl apply -f ${OUTPUT_FILE}"
