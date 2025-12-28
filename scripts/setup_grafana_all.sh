#!/usr/bin/env bash
#
# Complete Grafana Setup Script
# Runs all Grafana setup steps in sequence
#
# Version: 1.0.0
# Date: 2025-12-27
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# PROJECT_ROOT is not used in this script, but kept for consistency with other scripts
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck disable=SC2034
readonly PROJECT_ROOT

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
# Run setup step
##
run_step() {
    local step_name="${1}"
    local script_path="${2}"

    print_message "${BLUE}" ""
    print_message "${BLUE}" "=========================================="
    print_message "${GREEN}" "Step: ${step_name}"
    print_message "${BLUE}" "=========================================="
    echo

    if [[ ! -f "${script_path}" ]]; then
        print_message "${RED}" "✗ Script not found: ${script_path}"
        return 1
    fi

    if bash "${script_path}"; then
        print_message "${GREEN}" "✓ ${step_name} completed"
        return 0
    else
        print_message "${RED}" "✗ ${step_name} failed"
        return 1
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "Complete Grafana Setup for OSM Notes Monitoring"
    echo
    print_message "${BLUE}" "This script will run all Grafana setup steps:"
    echo "  1. Install and configure Grafana"
    echo "  2. Set up PostgreSQL data source"
    echo "  3. Configure authentication"
    echo "  4. Set up dashboard provisioning"
    echo

    read -p "Continue with complete setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "${YELLOW}" "Setup cancelled"
        exit 0
    fi

    local failed_steps=()

    # Step 1: Install Grafana
    if ! run_step "Install Grafana" "${SCRIPT_DIR}/setup_grafana.sh"; then
        failed_steps+=("Install Grafana")
    fi

    # Step 2: Set up PostgreSQL data source
    if ! run_step "Set up PostgreSQL data source" "${SCRIPT_DIR}/setup_grafana_datasource.sh"; then
        failed_steps+=("Set up PostgreSQL data source")
    fi

    # Step 3: Configure authentication
    if ! run_step "Configure authentication" "${SCRIPT_DIR}/setup_grafana_auth.sh"; then
        failed_steps+=("Configure authentication")
    fi

    # Step 4: Set up dashboard provisioning
    if ! run_step "Set up dashboard provisioning" "${SCRIPT_DIR}/setup_grafana_provisioning.sh"; then
        failed_steps+=("Set up dashboard provisioning")
    fi

    # Summary
    echo
    print_message "${BLUE}" "=========================================="
    print_message "${GREEN}" "Setup Summary"
    print_message "${BLUE}" "=========================================="
    echo

    if [[ ${#failed_steps[@]} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All setup steps completed successfully!"
        echo
        print_message "${YELLOW}" "Next steps:"
        echo "  1. Access Grafana at: http://localhost:3000"
        echo "  2. Login with default credentials (change password immediately)"
        echo "  3. Verify dashboards are imported"
        echo "  4. Test data source connection"
    else
        print_message "${RED}" "✗ Some steps failed:"
        for step in "${failed_steps[@]}"; do
            print_message "${RED}" "  - ${step}"
        done
        echo
        print_message "${YELLOW}" "Please review the errors above and run failed steps manually"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
