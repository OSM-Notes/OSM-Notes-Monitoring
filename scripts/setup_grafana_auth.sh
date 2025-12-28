#!/usr/bin/env bash
#
# Grafana Authentication Setup Script
# Configures authentication settings for Grafana
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
readonly GRAFANA_CONTAINER_NAME="${GRAFANA_CONTAINER_NAME:-osm-notes-grafana}"
readonly GRAFANA_CONFIG_DIR="${GRAFANA_CONFIG_DIR:-/etc/grafana}"
readonly GRAFANA_CONFIG_FILE="${GRAFANA_CONFIG_FILE:-grafana.ini}"

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
# Configure basic authentication settings
##
configure_basic_auth() {
    print_message "${BLUE}" "Configuring basic authentication settings..."

    local config_path
    if is_docker_installation; then
        config_path="/etc/grafana/${GRAFANA_CONFIG_FILE}"
    else
        config_path="${GRAFANA_CONFIG_DIR}/${GRAFANA_CONFIG_FILE}"
    fi

    # Read current config
    local temp_config
    temp_config=$(mktemp)

    if is_docker_installation; then
        docker exec "${GRAFANA_CONTAINER_NAME}" cat "${config_path}" > "${temp_config}" 2>/dev/null || true
    else
        # Use tee instead of redirect with sudo
        sudo cat "${config_path}" 2>/dev/null | tee "${temp_config}" > /dev/null 2>&1 || true
    fi

    # Configure settings
    print_message "${BLUE}" "Setting authentication options..."

    # Disable sign-up by default
    if ! grep -q "^allow_sign_up" "${temp_config}" 2>/dev/null; then
        {
            echo ""
            echo "[users]"
            echo "allow_sign_up = false"
        } >> "${temp_config}"
    else
        sed -i 's/^allow_sign_up.*/allow_sign_up = false/' "${temp_config}"
    fi

    # Set default admin user (if not already set)
    if ! grep -q "^admin_user" "${temp_config}" 2>/dev/null; then
        echo "admin_user = admin" >> "${temp_config}"
    fi

    # Copy config back
    if is_docker_installation; then
        docker cp "${temp_config}" "${GRAFANA_CONTAINER_NAME}:${config_path}"
        docker exec "${GRAFANA_CONTAINER_NAME}" chown root:root "${config_path}"
    else
        sudo cp "${temp_config}" "${config_path}"
        sudo chown root:root "${config_path}"
    fi

    rm -f "${temp_config}"

    print_message "${GREEN}" "✓ Basic authentication configured"
}

##
# Prompt for password change
##
prompt_password_change() {
    print_message "${YELLOW}" ""
    print_message "${YELLOW}" "IMPORTANT: Change the default admin password on first login!"
    print_message "${YELLOW}" "Access Grafana and go to: Administration → Users → admin → Change Password"
    echo
}

##
# Configure LDAP (optional)
##
configure_ldap() {
    print_message "${BLUE}" "LDAP configuration is optional and requires manual setup."
    print_message "${YELLOW}" "See docs/GRAFANA_SETUP_GUIDE.md for LDAP configuration instructions."
    echo
}

##
# Configure OAuth (optional)
##
configure_oauth() {
    print_message "${BLUE}" "OAuth configuration is optional and requires manual setup."
    print_message "${YELLOW}" "See docs/GRAFANA_SETUP_GUIDE.md for OAuth configuration instructions."
    echo
}

##
# Main
##
main() {
    print_message "${GREEN}" "Grafana Authentication Setup"
    echo

    if is_docker_installation; then
        print_message "${BLUE}" "Detected Docker installation"
    else
        print_message "${BLUE}" "Detected package installation"
    fi

    echo
    print_message "${BLUE}" "This script will configure basic authentication settings."
    print_message "${YELLOW}" "For LDAP or OAuth, please configure manually using the guide."
    echo

    read -p "Continue with basic authentication setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "${YELLOW}" "Setup cancelled"
        exit 0
    fi

    if configure_basic_auth; then
        echo
        prompt_password_change
        echo
        print_message "${GREEN}" "Setup complete!"
        print_message "${YELLOW}" "Next steps:"
        echo "  1. Restart Grafana to apply changes"
        echo "  2. Login and change default admin password"
        echo "  3. Configure LDAP/OAuth if needed (see docs/GRAFANA_SETUP_GUIDE.md)"
        echo
        read -p "Restart Grafana now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if is_docker_installation; then
                docker restart "${GRAFANA_CONTAINER_NAME}" > /dev/null 2>&1
                print_message "${GREEN}" "✓ Grafana container restarted"
            else
                sudo systemctl restart grafana-server > /dev/null 2>&1
                print_message "${GREEN}" "✓ Grafana service restarted"
            fi
        fi
    else
        print_message "${RED}" "Setup failed"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
