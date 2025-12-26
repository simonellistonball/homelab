#!/bin/bash

# Generate secure passwords for config.env
# Run this once before first deployment

set -e

echo "Generating secure passwords..."
echo ""

# Function to generate a secure password
generate_password() {
    openssl rand -base64 24 | tr -d '/+=' | head -c 32
}

# Function to generate a hex key
generate_hex_key() {
    openssl rand -hex 32
}

# Function to generate S3-style access key (20 chars uppercase alphanumeric)
generate_s3_access_key() {
    openssl rand -base64 20 | tr -d '/+=' | tr '[:lower:]' '[:upper:]' | head -c 20
}

# Function to generate S3-style secret key (40 chars)
generate_s3_secret_key() {
    openssl rand -base64 40 | tr -d '/+=' | head -c 40
}

cat << EOF
# ============================================
# PostgreSQL Database Passwords
# ============================================
export POSTGRES_N8N_PASSWORD="$(generate_password)"
export POSTGRES_GITEA_PASSWORD="$(generate_password)"
export POSTGRES_HARBOR_PASSWORD="$(generate_password)"
export POSTGRES_DAGSTER_PASSWORD="$(generate_password)"
export POSTGRES_LITELLM_PASSWORD="$(generate_password)"
export POSTGRES_IMMICH_PASSWORD="$(generate_password)"
export POSTGRES_FRIGATE_PASSWORD="$(generate_password)"

# ============================================
# Redis
# ============================================
export REDIS_PASSWORD="$(generate_password)"

# ============================================
# Service Admin Passwords
# ============================================
export GITEA_ADMIN_PASSWORD="$(generate_password)"
export HARBOR_ADMIN_PASSWORD="$(generate_password)"
export GRAFANA_ADMIN_PASSWORD="$(generate_password)"

# ============================================
# LiteLLM Configuration
# ============================================
export LITELLM_MASTER_KEY="sk-$(generate_password)"
export LITELLM_SALT_KEY="sk-salt-$(generate_password)"

# ============================================
# n8n Configuration
# ============================================
export N8N_ENCRYPTION_KEY="$(generate_hex_key)"

# ============================================
# SeaweedFS S3 Configuration
# ============================================
export SEAWEEDFS_ACCESS_KEY="$(generate_s3_access_key)"
export SEAWEEDFS_SECRET_KEY="$(generate_s3_secret_key)"
export SEAWEEDFS_READONLY_ACCESS_KEY="$(generate_s3_access_key)"
export SEAWEEDFS_READONLY_SECRET_KEY="$(generate_s3_secret_key)"

EOF

echo ""
echo "Copy the above output and paste it into config.env"
echo "replacing the CHANGE_ME placeholder values."
echo ""
echo "IMPORTANT: Also update these passwords in your PostgreSQL server!"
