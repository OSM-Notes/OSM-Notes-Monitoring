#!/usr/bin/env bash
#
# Update Dashboard Script
# Updates dashboard data from metrics database
#
# Version: 1.0.0
# Date: 2025-12-27
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
readonly PROJECT_ROOT

# Source libraries
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Only initialize logging if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Initialize logging
    init_logging "${LOG_DIR}/update_dashboard.log" "updateDashboard"
fi

##
# Show usage
##
usage() {
    cat << EOF
Update Dashboard Script

Usage: ${0} [OPTIONS] [DASHBOARD_TYPE]

Arguments:
    DASHBOARD_TYPE    Dashboard type (grafana, html, or 'all') (default: all)

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    -d, --dashboard DIR Dashboard directory (default: dashboards/)
    --force             Force update even if data is recent
    --component COMP    Update specific component only

Examples:
    ${0} grafana                    # Update Grafana dashboards
    ${0} html                      # Update HTML dashboards
    ${0} all                       # Update all dashboards
    ${0} --component ingestion all # Update ingestion component only

EOF
}

##
# Load configuration
##
load_config() {
    local config_file="${1:-${PROJECT_ROOT}/config/monitoring.conf}"
    
    if [[ -f "${config_file}" ]]; then
        # shellcheck disable=SC1090
        source "${config_file}" || true
    fi
    
    # Set defaults
    export DASHBOARD_UPDATE_INTERVAL="${DASHBOARD_UPDATE_INTERVAL:-300}"  # 5 minutes
    export DASHBOARD_OUTPUT_DIR="${DASHBOARD_OUTPUT_DIR:-${PROJECT_ROOT}/dashboards}"
}

##
# Check if dashboard needs update
#
# Arguments:
#   $1 - Dashboard file path
#   $2 - Update interval in seconds
##
needs_update() {
    local dashboard_file="${1:?Dashboard file required}"
    local update_interval="${2:-300}"
    
    if [[ ! -f "${dashboard_file}" ]]; then
        return 0  # File doesn't exist, needs update
    fi
    
    local file_age
    file_age=$(($(date +%s) - $(stat -c %Y "${dashboard_file}" 2>/dev/null || echo "0")))
    
    if [[ "${file_age}" -gt "${update_interval}" ]]; then
        return 0  # File is older than interval, needs update
    fi
    
    return 1  # File is recent, no update needed
}

##
# Update Grafana dashboard data
#
# Arguments:
#   $1 - Component name (optional)
##
update_grafana_dashboard() {
    local component="${1:-}"
    local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/grafana"
    local metrics_script="${SCRIPT_DIR}/generateMetrics.sh"
    
    mkdir -p "${dashboard_dir}"
    
    if [[ -n "${component}" ]]; then
        log_info "Updating Grafana dashboard for component: ${component}"
        "${metrics_script}" "${component}" dashboard > "${dashboard_dir}/${component}_metrics.json" 2>/dev/null || true
    else
        log_info "Updating all Grafana dashboards"
        local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
        
        for comp in "${components[@]}"; do
            log_info "Updating Grafana dashboard for component: ${comp}"
            "${metrics_script}" "${comp}" dashboard > "${dashboard_dir}/${comp}_metrics.json" 2>/dev/null || true
        done
    fi
    
    log_info "Grafana dashboards updated"
}

##
# Update HTML dashboard data
#
# Arguments:
#   $1 - Component name (optional)
##
update_html_dashboard() {
    local component="${1:-}"
    local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/html"
    local metrics_script="${SCRIPT_DIR}/generateMetrics.sh"
    
    mkdir -p "${dashboard_dir}"
    
    if [[ -n "${component}" ]]; then
        log_info "Updating HTML dashboard for component: ${component}"
        "${metrics_script}" "${component}" json > "${dashboard_dir}/${component}_data.json" 2>/dev/null || true
    else
        log_info "Updating all HTML dashboards"
        local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
        
        for comp in "${components[@]}"; do
            log_info "Updating HTML dashboard for component: ${comp}"
            "${metrics_script}" "${comp}" json > "${dashboard_dir}/${comp}_data.json" 2>/dev/null || true
        done
        
        # Generate overview data
        log_info "Generating overview data"
        "${metrics_script}" all json > "${dashboard_dir}/overview_data.json" 2>/dev/null || true
    fi
    
    log_info "HTML dashboards updated"
}

##
# Update component health status
##
update_component_health() {
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    log_info "Updating component health status"
    
    local query="
        WITH latest_metrics AS (
            SELECT DISTINCT ON (component)
                component,
                timestamp,
                CASE 
                    WHEN COUNT(*) FILTER (WHERE metric_name LIKE '%error%' OR metric_name LIKE '%failure%') > 0 THEN 'degraded'
                    WHEN COUNT(*) FILTER (WHERE metric_name LIKE '%availability%' AND metric_value::numeric < 1) > 0 THEN 'down'
                    WHEN MAX(timestamp) < CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 'unknown'
                    ELSE 'healthy'
                END as status
            FROM metrics
            WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
            GROUP BY component, timestamp
            ORDER BY component, timestamp DESC
        )
        INSERT INTO component_health (component, status, last_check, last_success)
        SELECT 
            component,
            status,
            CURRENT_TIMESTAMP,
            CASE WHEN status = 'healthy' THEN CURRENT_TIMESTAMP ELSE last_success END
        FROM latest_metrics
        ON CONFLICT (component) DO UPDATE SET
            status = EXCLUDED.status,
            last_check = EXCLUDED.last_check,
            last_success = EXCLUDED.last_success,
            error_count = CASE 
                WHEN EXCLUDED.status != 'healthy' THEN component_health.error_count + 1
                ELSE 0
            END;
    "
    
    # Use PGPASSWORD only if set, otherwise let psql use default authentication
    if [[ -n "${PGPASSWORD:-}" ]]; then
        PGPASSWORD="${PGPASSWORD}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -c "${query}" > /dev/null 2>&1 || log_warning "Failed to update component health"
    else
        psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1 || log_warning "Failed to update component health"
    fi
}

##
# Main function
##
main() {
    local dashboard_type="${1:-all}"
    local component="${2:-}"
    local force_update="${3:-false}"
    
    # Load configuration
    load_config "${CONFIG_FILE:-}"
    
    # Update component health
    update_component_health
    
    # Update dashboards based on type
    case "${dashboard_type}" in
        grafana)
            if [[ "${force_update}" == "true" ]] || needs_update "${DASHBOARD_OUTPUT_DIR}/grafana/overview_metrics.json" "${DASHBOARD_UPDATE_INTERVAL}"; then
                update_grafana_dashboard "${component}"
            else
                log_info "Grafana dashboards are up to date"
            fi
            ;;
        html)
            if [[ "${force_update}" == "true" ]] || needs_update "${DASHBOARD_OUTPUT_DIR}/html/overview_data.json" "${DASHBOARD_UPDATE_INTERVAL}"; then
                update_html_dashboard "${component}"
            else
                log_info "HTML dashboards are up to date"
            fi
            ;;
        all)
            if [[ "${force_update}" == "true" ]] || needs_update "${DASHBOARD_OUTPUT_DIR}/html/overview_data.json" "${DASHBOARD_UPDATE_INTERVAL}"; then
                update_html_dashboard "${component}"
            fi
            if [[ "${force_update}" == "true" ]] || needs_update "${DASHBOARD_OUTPUT_DIR}/grafana/overview_metrics.json" "${DASHBOARD_UPDATE_INTERVAL}"; then
                update_grafana_dashboard "${component}"
            fi
            if [[ "${force_update}" != "true" ]]; then
                log_info "Dashboards are up to date"
            fi
            ;;
        *)
            log_error "Unknown dashboard type: ${dashboard_type}"
            usage
            exit 1
            ;;
    esac
    
    log_info "Dashboard update completed"
}

# Parse command line arguments
DASHBOARD_TYPE="all"
COMPONENT=""
FORCE_UPDATE="false"

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
            shift
            ;;
        -q|--quiet)
            export LOG_LEVEL="${LOG_LEVEL_ERROR}"
            shift
            ;;
        -c|--config)
            export CONFIG_FILE="${2}"
            shift 2
            ;;
        -d|--dashboard)
            export DASHBOARD_OUTPUT_DIR="${2}"
            shift 2
            ;;
        --force)
            FORCE_UPDATE="true"
            shift
            ;;
        --component)
            COMPONENT="${2}"
            shift 2
            ;;
        *)
            DASHBOARD_TYPE="${1}"
            shift
            ;;
    esac
done

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "${DASHBOARD_TYPE}" "${COMPONENT}" "${FORCE_UPDATE}"
fi
