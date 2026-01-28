#!/usr/bin/env bash
#
# Configuration Template Generator
# Generates configuration files from templates
#
# Version: 1.0.0
# Date: 2025-12-24
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
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
# Print usage
##
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [CONFIG_TYPE]

Generate configuration files from templates.

Options:
    -a, --all              Generate all configuration files
    -f, --force            Overwrite existing files
    -i, --interactive      Interactive mode (prompt for values)
    -o, --output DIR       Output directory (default: original location)
    -h, --help             Show this help message

Config Types:
    main                   Main configuration (etc/properties.sh)
    monitoring             Monitoring configuration (config/monitoring.conf)
    alerts                 Alert configuration (config/alerts.conf)
    security               Security configuration (config/security.conf)
    all                    All configurations (default)

Examples:
    $0                     # Generate all configs interactively
    $0 -a                  # Generate all configs with defaults
    $0 -f main             # Force generate main config
    $0 -i monitoring       # Interactive generation for monitoring config

EOF
}

##
# Generate main configuration
##
generate_main_config() {
    local force="${1:-false}"
    local interactive="${2:-false}"
    local output_dir="${3:-}"

    local template="${PROJECT_ROOT}/etc/properties.sh.example"
    local target="${output_dir:-${PROJECT_ROOT}/etc}/properties.sh"

    if [[ ! -f "${template}" ]]; then
        print_message "${RED}" "Template not found: ${template}"
        return 1
    fi

    if [[ -f "${target}" && "${force}" != "true" ]]; then
        print_message "${YELLOW}" "Configuration file already exists: ${target}"
        print_message "${YELLOW}" "Use -f/--force to overwrite"
        return 1
    fi

    if [[ "${interactive}" == "true" ]]; then
        generate_interactive_main_config "${target}" "${template}"
    else
        cp "${template}" "${target}"
        print_message "${GREEN}" "Generated: ${target}"
        print_message "${YELLOW}" "Please edit ${target} with your configuration"
    fi

    return 0
}

##
# Generate monitoring configuration
##
generate_monitoring_config() {
    local force="${1:-false}"
    local interactive="${2:-false}"
    local output_dir="${3:-}"

    local template="${PROJECT_ROOT}/config/monitoring.conf.example"
    local target="${output_dir:-${PROJECT_ROOT}/config}/monitoring.conf"

    if [[ ! -f "${template}" ]]; then
        print_message "${RED}" "Template not found: ${template}"
        return 1
    fi

    if [[ -f "${target}" && "${force}" != "true" ]]; then
        print_message "${YELLOW}" "Configuration file already exists: ${target}"
        print_message "${YELLOW}" "Use -f/--force to overwrite"
        return 1
    fi

    cp "${template}" "${target}"
    print_message "${GREEN}" "Generated: ${target}"

    if [[ "${interactive}" != "true" ]]; then
        print_message "${YELLOW}" "Please edit ${target} with your configuration"
    fi

    return 0
}

##
# Generate alert configuration
##
generate_alert_config() {
    local force="${1:-false}"
    local interactive="${2:-false}"
    local output_dir="${3:-}"

    local template="${PROJECT_ROOT}/config/alerts.conf.example"
    local target="${output_dir:-${PROJECT_ROOT}/config}/alerts.conf"

    if [[ ! -f "${template}" ]]; then
        print_message "${RED}" "Template not found: ${template}"
        return 1
    fi

    if [[ -f "${target}" && "${force}" != "true" ]]; then
        print_message "${YELLOW}" "Configuration file already exists: ${target}"
        print_message "${YELLOW}" "Use -f/--force to overwrite"
        return 1
    fi

    if [[ "${interactive}" == "true" ]]; then
        generate_interactive_alert_config "${target}" "${template}"
    else
        cp "${template}" "${target}"
        print_message "${GREEN}" "Generated: ${target}"
        print_message "${YELLOW}" "Please edit ${target} with your configuration"
    fi

    return 0
}

##
# Generate security configuration
##
generate_security_config() {
    local force="${1:-false}"
    local interactive="${2:-false}"
    local output_dir="${3:-}"

    local template="${PROJECT_ROOT}/config/security.conf.example"
    local target="${output_dir:-${PROJECT_ROOT}/config}/security.conf"

    if [[ ! -f "${template}" ]]; then
        print_message "${RED}" "Template not found: ${template}"
        return 1
    fi

    if [[ -f "${target}" && "${force}" != "true" ]]; then
        print_message "${YELLOW}" "Configuration file already exists: ${target}"
        print_message "${YELLOW}" "Use -f/--force to overwrite"
        return 1
    fi

    cp "${template}" "${target}"
    print_message "${GREEN}" "Generated: ${target}"

    if [[ "${interactive}" != "true" ]]; then
        print_message "${YELLOW}" "Please edit ${target} with your configuration"
    fi

    return 0
}

##
# Generate interactive main config
##
generate_interactive_main_config() {
    local target="${1}"
    local template="${2}"

    print_message "${BLUE}" "Generating main configuration interactively..."
    echo

    # Read values
    read -r -p "Database name [osm_notes_monitoring]: " dbname
    dbname="${dbname:-osm_notes_monitoring}"

    read -r -p "Database host [localhost]: " dbhost
    dbhost="${dbhost:-localhost}"

    read -r -p "Database port [5432]: " dbport
    dbport="${dbport:-5432}"

    read -r -p "Database user [postgres]: " dbuser
    dbuser="${dbuser:-postgres}"

    read -r -p "Admin email: " admin_email

    read -r -p "Send alert emails? [true/false, default: true]: " send_email
    send_email="${send_email:-true}"

    # Generate config file
    cat > "${target}" << EOF
# Properties for OSM-Notes-Monitoring
# Generated: $(date +"%Y-%m-%d")
# Version: 2025-12-24

# Database
DBNAME="${dbname}"
DBHOST="${dbhost}"
DBPORT="${dbport}"
DBUSER="${dbuser}"

# Alerting
ADMIN_EMAIL="${admin_email}"
SEND_ALERT_EMAIL="${send_email}"
SLACK_WEBHOOK_URL=""  # Optional

# Monitoring Intervals (in seconds)
INGESTION_CHECK_INTERVAL=300      # 5 minutes
ANALYTICS_CHECK_INTERVAL=900       # 15 minutes
WMS_CHECK_INTERVAL=300             # 5 minutes
API_CHECK_INTERVAL=60              # 1 minute
DATA_CHECK_INTERVAL=3600           # 1 hour
INFRASTRUCTURE_CHECK_INTERVAL=300  # 5 minutes

# Logging
LOG_LEVEL="INFO"
LOG_DIR="/var/log/osm-notes-monitoring"
TMP_DIR="/var/tmp/osm-notes-monitoring"
LOCK_DIR="/var/run/osm-notes-monitoring"

# Repository Paths (adjust to your setup)
INGESTION_REPO_PATH="/path/to/OSM-Notes-Ingestion"
ANALYTICS_REPO_PATH="/path/to/OSM-Notes-Analytics"
WMS_REPO_PATH="/path/to/OSM-Notes-WMS"
DATA_REPO_PATH="/path/to/OSM-Notes-Data"
EOF

    print_message "${GREEN}" "Generated: ${target}"
}

##
# Generate interactive alert config
##
generate_interactive_alert_config() {
    local target="${1}"
    local template="${2}"

    print_message "${BLUE}" "Generating alert configuration interactively..."
    echo

    read -r -p "Admin email: " admin_email

    read -r -p "Send alert emails? [true/false, default: true]: " send_email
    send_email="${send_email:-true}"

    read -r -p "Enable Slack? [true/false, default: false]: " slack_enabled
    slack_enabled="${slack_enabled:-false}"

    local slack_webhook=""
    local slack_channel="#monitoring"

    if [[ "${slack_enabled}" == "true" ]]; then
        read -r -p "Slack webhook URL: " slack_webhook
        read -r -p "Slack channel [${slack_channel}]: " slack_channel_input
        slack_channel="${slack_channel_input:-${slack_channel}}"
    fi

    # Generate config file
    cat > "${target}" << EOF
# Alerting Configuration
# Generated: $(date +"%Y-%m-%d")
# Version: 2025-12-24

# Email
ADMIN_EMAIL="${admin_email}"
SEND_ALERT_EMAIL="${send_email}"

# Slack (optional)
SLACK_ENABLED="${slack_enabled}"
SLACK_WEBHOOK_URL="${slack_webhook}"
SLACK_CHANNEL="${slack_channel}"

# Alert Levels
CRITICAL_ALERT_RECIPIENTS="${admin_email}"
WARNING_ALERT_RECIPIENTS="${admin_email}"
INFO_ALERT_RECIPIENTS=""  # Optional, leave empty to disable

# Alert Deduplication
ALERT_DEDUPLICATION_ENABLED="true"
ALERT_DEDUPLICATION_WINDOW_MINUTES=60
EOF

    print_message "${GREEN}" "Generated: ${target}"
}

##
# Generate all configurations
##
generate_all_configs() {
    local force="${1:-false}"
    local interactive="${2:-false}"
    local output_dir="${3:-}"

    print_message "${BLUE}" "Generating all configuration files..."
    echo

    local errors=0

    generate_main_config "${force}" "${interactive}" "${output_dir}" || errors=$((errors + 1))
    generate_monitoring_config "${force}" "${interactive}" "${output_dir}" || errors=$((errors + 1))
    generate_alert_config "${force}" "${interactive}" "${output_dir}" || errors=$((errors + 1))
    generate_security_config "${force}" "${interactive}" "${output_dir}" || errors=$((errors + 1))

    echo
    if [[ ${errors} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All configuration files generated successfully"
        return 0
    else
        print_message "${RED}" "✗ Some configuration files failed to generate"
        return 1
    fi
}

##
# Main
##
main() {
    local force=false
    local interactive=false
    local output_dir=""
    local config_type="all"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -a|--all)
                config_type="all"
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -o|--output)
                output_dir="${2}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            main|monitoring|alerts|security|all)
                config_type="${1}"
                shift
                ;;
            -*)
                print_message "${RED}" "Unknown option: ${1}"
                usage
                exit 1
                ;;
            *)
                print_message "${RED}" "Unexpected argument: ${1}"
                usage
                exit 1
                ;;
        esac
    done

    # Ensure output directory exists
    if [[ -n "${output_dir}" ]]; then
        mkdir -p "${output_dir}/etc" "${output_dir}/config" 2>/dev/null || true
    fi

    # Generate requested config(s)
    case "${config_type}" in
        main)
            generate_main_config "${force}" "${interactive}" "${output_dir}"
            ;;
        monitoring)
            generate_monitoring_config "${force}" "${interactive}" "${output_dir}"
            ;;
        alerts)
            generate_alert_config "${force}" "${interactive}" "${output_dir}"
            ;;
        security)
            generate_security_config "${force}" "${interactive}" "${output_dir}"
            ;;
        all|*)
            generate_all_configs "${force}" "${interactive}" "${output_dir}"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

