#!/bin/bash
#
# Generate postgres-setup.sql with actual passwords from config.env
#
# Usage:
#   ./generate-postgres-sql.sh
#
# This creates postgres-setup.sql which you can copy to your PostgreSQL server.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

OUTPUT_FILE="${SCRIPT_DIR}/postgres-setup.sql"
TEMPLATE_FILE="${SCRIPT_DIR}/postgres-setup.sql.template"

# Check for placeholder passwords
check_passwords() {
    local has_placeholder=false
    local passwords=(
        "POSTGRES_N8N_PASSWORD"
        "POSTGRES_GITEA_PASSWORD"
        "POSTGRES_HARBOR_PASSWORD"
        "POSTGRES_DAGSTER_PASSWORD"
        "POSTGRES_LITELLM_PASSWORD"
        "POSTGRES_IMMICH_PASSWORD"
        "POSTGRES_FRIGATE_PASSWORD"
    )

    for var in "${passwords[@]}"; do
        if [[ "${!var}" == *"CHANGE_ME"* ]]; then
            echo "ERROR: $var is still a placeholder!"
            has_placeholder=true
        fi
    done

    if [ "$has_placeholder" = true ]; then
        echo ""
        echo "Please run ./generate-passwords.sh and update config.env first!"
        exit 1
    fi
}

echo "Checking passwords..."
check_passwords

echo "Generating postgres-setup.sql..."

# Escape special characters for sed (especially & and /)
escape_for_sed() {
    echo "$1" | sed -e 's/[\/&]/\\&/g'
}

cat "$TEMPLATE_FILE" | \
    sed "s/__POSTGRES_N8N_PASSWORD__/$(escape_for_sed "$POSTGRES_N8N_PASSWORD")/g" | \
    sed "s/__POSTGRES_GITEA_PASSWORD__/$(escape_for_sed "$POSTGRES_GITEA_PASSWORD")/g" | \
    sed "s/__POSTGRES_HARBOR_PASSWORD__/$(escape_for_sed "$POSTGRES_HARBOR_PASSWORD")/g" | \
    sed "s/__POSTGRES_DAGSTER_PASSWORD__/$(escape_for_sed "$POSTGRES_DAGSTER_PASSWORD")/g" | \
    sed "s/__POSTGRES_LITELLM_PASSWORD__/$(escape_for_sed "$POSTGRES_LITELLM_PASSWORD")/g" | \
    sed "s/__POSTGRES_IMMICH_PASSWORD__/$(escape_for_sed "$POSTGRES_IMMICH_PASSWORD")/g" | \
    sed "s/__POSTGRES_FRIGATE_PASSWORD__/$(escape_for_sed "$POSTGRES_FRIGATE_PASSWORD")/g" \
    > "$OUTPUT_FILE"

echo ""
echo "Created: $OUTPUT_FILE"
echo ""
echo "To apply on your PostgreSQL server (192.168.1.103):"
echo ""
echo "  Option 1 - Copy and run:"
echo "    scp $OUTPUT_FILE root@192.168.1.103:/tmp/"
echo "    ssh root@192.168.1.103 'sudo -u postgres psql < /tmp/postgres-setup.sql'"
echo ""
echo "  Option 2 - Run directly with psql:"
echo "    psql -h 192.168.1.103 -U postgres < $OUTPUT_FILE"
echo ""
echo "WARNING: postgres-setup.sql contains passwords. Delete it after use!"
