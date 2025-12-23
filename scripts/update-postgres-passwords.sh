#!/bin/bash
#
# Update PostgreSQL passwords for all homelab services
#
# Prerequisites:
#   - psql client installed locally, OR
#   - SSH access to the PostgreSQL server
#
# Usage:
#   ./update-postgres-passwords.sh [--create-users] [--create-databases]
#
# Options:
#   --create-users      Create users if they don't exist
#   --create-databases  Create databases if they don't exist
#   --dry-run          Show what would be done without making changes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

# Parse arguments
CREATE_USERS=false
CREATE_DATABASES=false
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --create-users)
            CREATE_USERS=true
            ;;
        --create-databases)
            CREATE_DATABASES=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --help)
            echo "Usage: $0 [--create-users] [--create-databases] [--dry-run]"
            exit 0
            ;;
    esac
done

# PostgreSQL connection settings
PG_HOST="${POSTGRES_HOST:-192.168.1.103}"
PG_PORT="${POSTGRES_PORT:-5432}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Define users and their databases
declare -A USERS=(
    ["n8n"]="${POSTGRES_N8N_PASSWORD}"
    ["gitea"]="${POSTGRES_GITEA_PASSWORD}"
    ["harbor"]="${POSTGRES_HARBOR_PASSWORD}"
    ["dagster"]="${POSTGRES_DAGSTER_PASSWORD}"
    ["litellm"]="${POSTGRES_LITELLM_PASSWORD}"
    ["immich"]="${POSTGRES_IMMICH_PASSWORD}"
    ["frigate"]="${POSTGRES_FRIGATE_PASSWORD}"
)

# Additional databases for Harbor (if needed)
declare -A EXTRA_DATABASES=(
    ["harbor"]="harbor harbor_notary_server harbor_notary_signer"
)

# Check for placeholder passwords
check_passwords() {
    local has_placeholder=false
    for user in "${!USERS[@]}"; do
        if [[ "${USERS[$user]}" == *"CHANGE_ME"* ]]; then
            log_error "Password for '$user' is still a placeholder!"
            has_placeholder=true
        fi
    done

    if [ "$has_placeholder" = true ]; then
        echo ""
        log_error "Please run ./generate-passwords.sh and update config.env first!"
        exit 1
    fi
}

# Generate SQL commands
generate_sql() {
    local user="$1"
    local password="$2"
    local databases="${3:-$user}"

    local sql=""

    if [ "$CREATE_USERS" = true ]; then
        sql+="DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${user}') THEN
        CREATE ROLE ${user} WITH LOGIN PASSWORD '${password}';
        RAISE NOTICE 'Created user ${user}';
    END IF;
END
\$\$;
"
    fi

    # Update password
    sql+="ALTER USER ${user} WITH PASSWORD '${password}';
"

    if [ "$CREATE_DATABASES" = true ]; then
        for db in $databases; do
            sql+="SELECT 'CREATE DATABASE ${db} OWNER ${user}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db}')\\gexec
GRANT ALL PRIVILEGES ON DATABASE ${db} TO ${user};
"
        done
    fi

    echo "$sql"
}

# Execute SQL via psql
execute_sql() {
    local sql="$1"

    if [ "$DRY_RUN" = true ]; then
        echo "$sql"
        return 0
    fi

    # Try local psql first
    if command -v psql &> /dev/null; then
        echo "$sql" | PGPASSWORD="${POSTGRES_ADMIN_PASSWORD:-}" psql -h "$PG_HOST" -p "$PG_PORT" -U postgres -v ON_ERROR_STOP=1
    else
        log_error "psql not found. Please install postgresql-client or run manually."
        echo ""
        echo "SQL to execute:"
        echo "$sql"
        return 1
    fi
}

# Main
main() {
    echo "========================================"
    echo "  PostgreSQL Password Update Script"
    echo "========================================"
    echo ""
    echo "Target: ${PG_HOST}:${PG_PORT}"
    echo ""

    check_passwords

    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN - No changes will be made"
        echo ""
    fi

    # Check if we have admin password
    if [ -z "${POSTGRES_ADMIN_PASSWORD:-}" ] && [ "$DRY_RUN" = false ]; then
        echo -n "Enter PostgreSQL admin (postgres) password: "
        read -s POSTGRES_ADMIN_PASSWORD
        echo ""
        export POSTGRES_ADMIN_PASSWORD
    fi

    local all_sql=""

    for user in "${!USERS[@]}"; do
        password="${USERS[$user]}"
        databases="${EXTRA_DATABASES[$user]:-$user}"

        log_info "Processing user: $user"

        sql=$(generate_sql "$user" "$password" "$databases")
        all_sql+="$sql"
        all_sql+="
"
    done

    echo ""
    if [ "$DRY_RUN" = true ]; then
        log_info "Generated SQL:"
        echo "----------------------------------------"
        echo "$all_sql"
        echo "----------------------------------------"
    else
        log_info "Executing SQL..."
        if execute_sql "$all_sql"; then
            log_info "All passwords updated successfully!"
        else
            log_error "Failed to update passwords"
            exit 1
        fi
    fi

    echo ""
    log_info "Done!"

    if [ "$DRY_RUN" = false ]; then
        echo ""
        echo "Next steps:"
        echo "  1. Test connections with the new passwords"
        echo "  2. Deploy/restart services that use these databases"
    fi
}

main "$@"
