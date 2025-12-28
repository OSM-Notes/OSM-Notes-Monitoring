#!/usr/bin/env bash
#
# Grafana Dashboard Provisioning Setup Script
# Sets up automatic dashboard provisioning for Grafana
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

# Default values
readonly GRAFANA_CONTAINER_NAME="${GRAFANA_CONTAINER_NAME:-osm-notes-grafana}"
readonly GRAFANA_PROVISIONING_DIR="${GRAFANA_PROVISIONING_DIR:-/etc/grafana/provisioning}"
readonly DASHBOARDS_DIR="${PROJECT_ROOT}/dashboards/grafana"

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
# Check if running in Docker
##
is_docker_installation() {
    if command_exists docker && docker ps --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER_NAME}$"; then
        return 0
    fi
    return 1
}

##
# Create dashboard provider configuration
##
create_dashboard_provider() {
    print_message "${BLUE}" "Creating dashboard provider configuration..."

    local provider_file
    if is_docker_installation; then
        # For Docker, create file locally and copy to container
        provider_file="${PROJECT_ROOT}/.grafana_provisioning/dashboards/dashboard.yml"
        mkdir -p "$(dirname "${provider_file}")"
    else
        # For package installation, create in system directory
        provider_file="${GRAFANA_PROVISIONING_DIR}/dashboards/dashboard.yml"
        sudo mkdir -p "$(dirname "${provider_file}")"
    fi

    cat > "${provider_file}" <<EOF
apiVersion: 1

providers:
  - name: 'OSM Notes Monitoring'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

    if is_docker_installation; then
        # Copy to Docker container
        docker cp "${provider_file}" "${GRAFANA_CONTAINER_NAME}:/etc/grafana/provisioning/dashboards/dashboard.yml"
        rm -rf "${PROJECT_ROOT}/.grafana_provisioning"
        print_message "${GREEN}" "✓ Dashboard provider configuration copied to container"
    else
        sudo chown grafana:grafana "${provider_file}" 2>/dev/null || true
        print_message "${GREEN}" "✓ Dashboard provider configuration created"
    fi
}

##
# Copy dashboards to provisioning directory
##
copy_dashboards() {
    print_message "${BLUE}" "Copying dashboards to provisioning directory..."

    if [[ ! -d "${DASHBOARDS_DIR}" ]]; then
        print_message "${RED}" "✗ Dashboards directory not found: ${DASHBOARDS_DIR}"
        return 1
    fi

    local dashboard_count
    dashboard_count=$(find "${DASHBOARDS_DIR}" -name "*.json" | wc -l)

    if [[ ${dashboard_count} -eq 0 ]]; then
        print_message "${YELLOW}" "⚠ No dashboard JSON files found in ${DASHBOARDS_DIR}"
        return 1
    fi

    if is_docker_installation; then
        # Copy dashboards to Docker container
        print_message "${BLUE}" "Copying ${dashboard_count} dashboards to Docker container..."

        # Create temporary directory
        local temp_dir
        temp_dir=$(mktemp -d)
        cp "${DASHBOARDS_DIR}"/*.json "${temp_dir}/"

        # Copy to container
        docker cp "${temp_dir}/." "${GRAFANA_CONTAINER_NAME}:/etc/grafana/provisioning/dashboards/"

        # Cleanup
        rm -rf "${temp_dir}"

        print_message "${GREEN}" "✓ ${dashboard_count} dashboards copied to container"
    else
        # Copy to system directory
        print_message "${BLUE}" "Copying ${dashboard_count} dashboards to system directory..."

        sudo mkdir -p "${GRAFANA_PROVISIONING_DIR}/dashboards"
        sudo cp "${DASHBOARDS_DIR}"/*.json "${GRAFANA_PROVISIONING_DIR}/dashboards/"
        sudo chown -R grafana:grafana "${GRAFANA_PROVISIONING_DIR}/dashboards"

        print_message "${GREEN}" "✓ ${dashboard_count} dashboards copied to system directory"
    fi
}

##
# Restart Grafana
##
restart_grafana() {
    print_message "${BLUE}" "Restarting Grafana to apply changes..."

    if is_docker_installation; then
        if docker restart "${GRAFANA_CONTAINER_NAME}" > /dev/null 2>&1; then
            print_message "${GREEN}" "✓ Grafana container restarted"
        else
            print_message "${RED}" "✗ Failed to restart Grafana container"
            return 1
        fi
    else
        if sudo systemctl restart grafana-server > /dev/null 2>&1; then
            print_message "${GREEN}" "✓ Grafana service restarted"
        else
            print_message "${RED}" "✗ Failed to restart Grafana service"
            return 1
        fi
    fi

    # Wait a bit for Grafana to start
    sleep 3
    return 0
}

##
# Verify provisioning
##
verify_provisioning() {
    print_message "${BLUE}" "Verifying dashboard provisioning..."

    local max_attempts=10
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if is_docker_installation; then
            if docker exec "${GRAFANA_CONTAINER_NAME}" \
                test -f /etc/grafana/provisioning/dashboards/dashboard.yml; then
                print_message "${GREEN}" "✓ Provisioning configuration verified"
                return 0
            fi
        else
            if [[ -f "${GRAFANA_PROVISIONING_DIR}/dashboards/dashboard.yml" ]]; then
                print_message "${GREEN}" "✓ Provisioning configuration verified"
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    print_message "${YELLOW}" "⚠ Could not verify provisioning automatically"
    return 0
}

##
# Main
##
main() {
    print_message "${GREEN}" "Grafana Dashboard Provisioning Setup"
    echo

    if is_docker_installation; then
        print_message "${BLUE}" "Detected Docker installation"
    else
        print_message "${BLUE}" "Detected package installation"
    fi

    echo
    print_message "${BLUE}" "Dashboards directory: ${DASHBOARDS_DIR}"

    local dashboard_count
    dashboard_count=$(find "${DASHBOARDS_DIR}" -name "*.json" 2>/dev/null | wc -l || echo "0")
    print_message "${BLUE}" "Found ${dashboard_count} dashboard(s)"

    echo
    read -p "Continue with provisioning setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "${YELLOW}" "Setup cancelled"
        exit 0
    fi

    if create_dashboard_provider && copy_dashboards; then
        echo
        if restart_grafana; then
            echo
            verify_provisioning
            echo
            print_message "${GREEN}" "Setup complete!"
            print_message "${YELLOW}" "Next steps:"
            echo "  1. Access Grafana and verify dashboards are imported"
            echo "  2. Dashboards should appear automatically in the dashboard list"
            echo "  3. If not, check Grafana logs for errors"
        else
            print_message "${YELLOW}" "⚠ Provisioning configured but Grafana restart failed"
            print_message "${YELLOW}" "Please restart Grafana manually"
        fi
    else
        print_message "${RED}" "Setup failed"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
