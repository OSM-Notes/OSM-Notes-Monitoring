#!/usr/bin/env bash
#
# Grafana Setup Script
# Installs and configures Grafana for OSM Notes Monitoring
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

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Default values
readonly GRAFANA_PORT="${GRAFANA_PORT:-3000}"
readonly GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
readonly GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
readonly GRAFANA_CONTAINER_NAME="${GRAFANA_CONTAINER_NAME:-osm-notes-grafana}"
readonly GRAFANA_DATA_DIR="${GRAFANA_DATA_DIR:-/var/lib/grafana}"

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

    local missing=()

    # Check for Docker or system package manager
    if ! command_exists docker && ! command_exists apt-get && ! command_exists yum; then
        missing+=("docker or apt-get/yum")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_message "${RED}" "Missing required tools: ${missing[*]}"
        return 1
    fi

    print_message "${GREEN}" "✓ Prerequisites met"
    return 0
}

##
# Install Grafana using Docker
##
install_grafana_docker() {
    print_message "${BLUE}" "Installing Grafana using Docker..."

    # Check if Docker is available
    if ! command_exists docker; then
        print_message "${RED}" "Docker is not installed. Please install Docker first."
        return 1
    fi

    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER_NAME}$"; then
        print_message "${YELLOW}" "Grafana container '${GRAFANA_CONTAINER_NAME}' already exists"
        read -p "Remove and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker stop "${GRAFANA_CONTAINER_NAME}" 2>/dev/null || true
            docker rm "${GRAFANA_CONTAINER_NAME}" 2>/dev/null || true
        else
            print_message "${YELLOW}" "Skipping Docker installation"
            return 0
        fi
    fi

    # Create data directory
    if [[ ! -d "${GRAFANA_DATA_DIR}" ]]; then
        sudo mkdir -p "${GRAFANA_DATA_DIR}"
        sudo chown 472:472 "${GRAFANA_DATA_DIR}" 2>/dev/null || true
    fi

    # Create provisioning directory
    local provisioning_dir="${PROJECT_ROOT}/dashboards/grafana"
    if [[ ! -d "${provisioning_dir}" ]]; then
        mkdir -p "${provisioning_dir}"
    fi

    # Run Grafana container
    if docker run -d \
        --name "${GRAFANA_CONTAINER_NAME}" \
        -p "${GRAFANA_PORT}:3000" \
        -v "${GRAFANA_DATA_DIR}:/var/lib/grafana" \
        -v "${provisioning_dir}:/etc/grafana/provisioning/dashboards:ro" \
        -e "GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}" \
        -e "GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}" \
        -e "GF_USERS_ALLOW_SIGN_UP=false" \
        --restart unless-stopped \
        grafana/grafana:latest; then
        print_message "${GREEN}" "✓ Grafana container started successfully"
        print_message "${GREEN}" "  Access Grafana at: http://localhost:${GRAFANA_PORT}"
        print_message "${GREEN}" "  Username: ${GRAFANA_ADMIN_USER}"
        print_message "${YELLOW}" "  Password: ${GRAFANA_ADMIN_PASSWORD} (change on first login)"
        return 0
    else
        print_message "${RED}" "✗ Failed to start Grafana container"
        return 1
    fi
}

##
# Install Grafana using package manager (Ubuntu/Debian)
##
install_grafana_ubuntu() {
    print_message "${BLUE}" "Installing Grafana using apt-get..."

    if ! command_exists apt-get; then
        print_message "${RED}" "apt-get is not available"
        return 1
    fi

    # Add Grafana repository
    print_message "${BLUE}" "Adding Grafana repository..."
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y "deb https://packages.grafana.com/oss/deb stable main"
    wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -

    # Update package list
    sudo apt-get update

    # Install Grafana
    if sudo apt-get install -y grafana; then
        print_message "${GREEN}" "✓ Grafana installed successfully"

        # Start and enable service
        sudo systemctl start grafana-server
        sudo systemctl enable grafana-server

        print_message "${GREEN}" "✓ Grafana service started and enabled"
        print_message "${GREEN}" "  Access Grafana at: http://localhost:${GRAFANA_PORT}"
        return 0
    else
        print_message "${RED}" "✗ Failed to install Grafana"
        return 1
    fi
}

##
# Install Grafana using package manager (CentOS/RHEL)
##
install_grafana_centos() {
    print_message "${BLUE}" "Installing Grafana using yum..."

    if ! command_exists yum; then
        print_message "${RED}" "yum is not available"
        return 1
    fi

    # Add Grafana repository
    print_message "${BLUE}" "Adding Grafana repository..."
    cat <<EOF | sudo tee /etc/yum.repos.d/grafana.repo
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

    # Install Grafana
    if sudo yum install -y grafana; then
        print_message "${GREEN}" "✓ Grafana installed successfully"

        # Start and enable service
        sudo systemctl start grafana-server
        sudo systemctl enable grafana-server

        print_message "${GREEN}" "✓ Grafana service started and enabled"
        print_message "${GREEN}" "  Access Grafana at: http://localhost:${GRAFANA_PORT}"
        return 0
    else
        print_message "${RED}" "✗ Failed to install Grafana"
        return 1
    fi
}

##
# Detect installation method
##
detect_installation_method() {
    if command_exists docker; then
        echo "docker"
    elif command_exists apt-get; then
        echo "ubuntu"
    elif command_exists yum; then
        echo "centos"
    else
        echo "unknown"
    fi
}

##
# Main installation function
##
install_grafana() {
    local method
    method=$(detect_installation_method)

    case "${method}" in
        docker)
            install_grafana_docker
            ;;
        ubuntu)
            install_grafana_ubuntu
            ;;
        centos)
            install_grafana_centos
            ;;
        *)
            print_message "${RED}" "Unable to detect installation method"
            print_message "${YELLOW}" "Please install Grafana manually or install Docker/apt-get/yum"
            return 1
            ;;
    esac
}

##
# Wait for Grafana to be ready
##
wait_for_grafana() {
    print_message "${BLUE}" "Waiting for Grafana to be ready..."
    local max_attempts=30
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if curl -s -f "http://localhost:${GRAFANA_PORT}/api/health" > /dev/null 2>&1; then
            print_message "${GREEN}" "✓ Grafana is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    print_message "${YELLOW}" "⚠ Grafana may not be ready yet. Please check manually."
    return 1
}

##
# Main
##
main() {
    print_message "${GREEN}" "Grafana Setup for OSM Notes Monitoring"
    echo

    if ! check_prerequisites; then
        exit 1
    fi

    echo
    print_message "${BLUE}" "Installation method will be auto-detected"
    print_message "${YELLOW}" "Available methods: Docker (preferred), Ubuntu/Debian (apt-get), CentOS/RHEL (yum)"
    echo

    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "${YELLOW}" "Installation cancelled"
        exit 0
    fi

    if install_grafana; then
        echo
        wait_for_grafana
        echo
        print_message "${GREEN}" "Setup complete!"
        print_message "${YELLOW}" "Next steps:"
        echo "  1. Access Grafana at: http://localhost:${GRAFANA_PORT}"
        echo "  2. Login with username: ${GRAFANA_ADMIN_USER}"
        echo "  3. Change password on first login"
        echo "  4. Run: ./scripts/setup_grafana_datasource.sh"
        echo "  5. Run: ./scripts/setup_grafana_provisioning.sh"
    else
        print_message "${RED}" "Installation failed"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
