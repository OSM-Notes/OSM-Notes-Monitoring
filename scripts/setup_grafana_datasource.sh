#!/usr/bin/env bash
#
# Grafana PostgreSQL Data Source Setup Script
# Configures PostgreSQL data source in Grafana via API
#
# Version: 1.0.0
# Date: 2025-12-27
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

# Load configuration
if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/etc/properties.sh"
fi

# Default values
readonly GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
readonly GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
readonly GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
readonly DBNAME="${DBNAME:-osm_notes_monitoring}"
readonly DBHOST="${DBHOST:-localhost}"
readonly DBPORT="${DBPORT:-5432}"
readonly DBUSER="${DBUSER:-postgres}"
readonly DBPASSWORD="${DBPASSWORD:-}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check if command exists
##
command_exists() {
    command -v "${1}" > /dev/null 2>&1
}

##
# Check prerequisites
##
check_prerequisites() {
    print_message "${BLUE}" "Checking prerequisites..."

    if ! command_exists curl; then
        print_message "${RED}" "curl is required but not installed"
        return 1
    fi

    # Check if Grafana is accessible
    if ! curl -s -f "${GRAFANA_URL}/api/health" > /dev/null 2>&1; then
        print_message "${RED}" "Cannot connect to Grafana at ${GRAFANA_URL}"
        print_message "${YELLOW}" "Please ensure Grafana is running"
        return 1
    fi

    print_message "${GREEN}" "✓ Prerequisites met"
    return 0
}

##
# Get Grafana API key or create one
##
get_api_key() {
    local api_key
    local response

    # Try to authenticate and get API key
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"osm-notes-monitoring\",\"role\":\"Admin\"}" \
        -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
        "${GRAFANA_URL}/api/auth/keys" 2>/dev/null)

    # Extract API key from response
    api_key=$(echo "${response}" | grep -o '"key":"[^"]*' | cut -d'"' -f4 || true)

    if [[ -z "${api_key}" ]]; then
        # If API key creation failed, try using basic auth
        echo "basic_auth"
    else
        echo "${api_key}"
    fi
}

##
# Create PostgreSQL data source
##
create_datasource() {
    print_message "${BLUE}" "Creating PostgreSQL data source..."

    local auth_method
    auth_method=$(get_api_key)

    # Prompt for database password if not set
    local db_password="${DBPASSWORD}"
    if [[ -z "${db_password}" ]]; then
        read -rsp "Enter PostgreSQL password for user ${DBUSER}: " db_password
        echo
    fi

    # Data source configuration
    local datasource_config
    datasource_config=$(cat <<EOF
{
  "name": "PostgreSQL",
  "type": "postgres",
  "url": "${DBHOST}:${DBPORT}",
  "user": "${DBUSER}",
  "secureJsonData": {
    "password": "${db_password}"
  },
  "database": "${DBNAME}",
  "jsonData": {
    "sslmode": "disable",
    "postgresVersion": 1200,
    "timescaledb": false
  },
  "isDefault": true,
  "access": "proxy"
}
EOF
)

    # Create data source via API
    local response
    if [[ "${auth_method}" == "basic_auth" ]]; then
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
            -d "${datasource_config}" \
            "${GRAFANA_URL}/api/datasources" 2>/dev/null)
    else
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${auth_method}" \
            -d "${datasource_config}" \
            "${GRAFANA_URL}/api/datasources" 2>/dev/null)
    fi

    local http_code
    http_code=$(echo "${response}" | tail -n1)
    local body
    body=$(echo "${response}" | sed '$d')

    if [[ "${http_code}" == "200" ]] || [[ "${http_code}" == "201" ]]; then
        print_message "${GREEN}" "✓ PostgreSQL data source created successfully"
        return 0
    elif echo "${body}" | grep -q "already exists"; then
        print_message "${YELLOW}" "⚠ Data source already exists"
        print_message "${BLUE}" "Updating existing data source..."

        # Get data source ID
        local ds_id
        ds_id=$(curl -s \
            -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
            "${GRAFANA_URL}/api/datasources/name/PostgreSQL" 2>/dev/null | \
            grep -o '"id":[0-9]*' | cut -d':' -f2 || echo "")

        if [[ -n "${ds_id}" ]]; then
            # Update data source
            if curl -s -w "\n%{http_code}" -X PUT \
                -H "Content-Type: application/json" \
                -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
                -d "${datasource_config}" \
                "${GRAFANA_URL}/api/datasources/${ds_id}" 2>/dev/null | \
                tail -n1 | grep -q "200"; then
                print_message "${GREEN}" "✓ Data source updated successfully"
                return 0
            fi
        fi
    fi

    print_message "${RED}" "✗ Failed to create/update data source"
    print_message "${YELLOW}" "Response: ${body}"
    return 1
}

##
# Test data source connection
##
test_datasource() {
    print_message "${BLUE}" "Testing data source connection..."

    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
        -d '{"id":1}' \
        "${GRAFANA_URL}/api/datasources/proxy/1/query" 2>/dev/null)

    if echo "${response}" | grep -q "success"; then
        print_message "${GREEN}" "✓ Data source connection test passed"
        return 0
    else
        print_message "${YELLOW}" "⚠ Could not test connection automatically"
        print_message "${YELLOW}" "Please test manually in Grafana UI"
        return 0
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "Grafana PostgreSQL Data Source Setup"
    echo

    if ! check_prerequisites; then
        exit 1
    fi

    echo
    print_message "${BLUE}" "Configuration:"
    echo "  Grafana URL: ${GRAFANA_URL}"
    echo "  Database: ${DBNAME}"
    echo "  Host: ${DBHOST}:${DBPORT}"
    echo "  User: ${DBUSER}"
    echo

    read -p "Continue with data source setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "${YELLOW}" "Setup cancelled"
        exit 0
    fi

    if create_datasource; then
        echo
        test_datasource
        echo
        print_message "${GREEN}" "Setup complete!"
        print_message "${YELLOW}" "Next steps:"
        echo "  1. Verify data source in Grafana UI: ${GRAFANA_URL}/datasources"
        echo "  2. Run: ./scripts/setup_grafana_provisioning.sh"
    else
        print_message "${RED}" "Setup failed"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
