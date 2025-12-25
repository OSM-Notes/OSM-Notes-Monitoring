#!/usr/bin/env bash
#
# Ingestion Monitoring Script
# Monitors the OSM-Notes-Ingestion component health and performance
#
# Version: 1.0.0
# Date: 2025-12-24
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
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"

# Initialize logging
init_logging "${LOG_DIR}/ingestion.log" "monitorIngestion"

# Component name
readonly COMPONENT="INGESTION"

##
# Show usage
##
usage() {
    cat << EOF
Ingestion Monitoring Script

Monitors the OSM-Notes-Ingestion component for health, performance, and data quality.

Usage: $0 [OPTIONS]

Options:
    -c, --check TYPE      Run specific check (health, performance, data-quality, all)
    -v, --verbose         Enable verbose output
    -d, --dry-run         Dry run (don't write to database)
    -h, --help            Show this help message

Check Types:
    health          Check component health status
    performance     Check performance metrics
    data-quality    Check data quality metrics
    all             Run all checks (default)

Examples:
    # Run all checks
    $0

    # Run only health check
    $0 --check health

    # Dry run (no database writes)
    $0 --dry-run

EOF
}

##
# Check ingestion component health
##
check_ingestion_health() {
    log_info "${COMPONENT}: Starting health check"
    
    local health_status="unknown"
    local error_message=""
    
    # Check if ingestion repository exists
    if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
        health_status="down"
        error_message="Ingestion repository not found: ${INGESTION_REPO_PATH}"
        log_error "${COMPONENT}: ${error_message}"
        record_metric "${COMPONENT}" "health_status" "0" "component=ingestion"
        send_alert "CRITICAL" "${COMPONENT}" "Health check failed: ${error_message}"
        return 1
    fi
    
    # Check if ingestion processes are running
    # TODO: Implement process check based on ingestion setup
    # This is a placeholder - actual implementation depends on ingestion architecture
    
    # Check if ingestion log files exist and are recent
    local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
    if [[ -d "${ingestion_log_dir}" ]]; then
        local latest_log
        latest_log=$(find "${ingestion_log_dir}" -name "*.log" -type f -mtime -1 2>/dev/null | head -1)
        
        if [[ -z "${latest_log}" ]]; then
            health_status="degraded"
            error_message="No recent log files found (older than 1 day)"
            log_warning "${COMPONENT}: ${error_message}"
            record_metric "${COMPONENT}" "health_status" "1" "component=ingestion"
            send_alert "WARNING" "${COMPONENT}" "Health check warning: ${error_message}"
            return 0
        fi
    fi
    
    # If we get here, component appears healthy
    # shellcheck disable=SC2034
    health_status="healthy"
    log_info "${COMPONENT}: Health check passed"
    record_metric "${COMPONENT}" "health_status" "1" "component=ingestion"
    
    return 0
}

##
# Check ingestion performance metrics
##
check_ingestion_performance() {
    log_info "${COMPONENT}: Starting performance check"
    
    # TODO: Implement performance metrics collection
    # This should check:
    # - Processing rate (notes per hour)
    # - Processing latency
    # - Error rate
    # - Queue depth (if applicable)
    
    log_info "${COMPONENT}: Performance check completed (placeholder)"
    
    return 0
}

##
# Check ingestion data quality
##
check_ingestion_data_quality() {
    log_info "${COMPONENT}: Starting data quality check"
    
    # TODO: Implement data quality checks
    # This should check:
    # - Data completeness
    # - Data accuracy
    # - Data freshness
    # - Duplicate detection
    
    log_info "${COMPONENT}: Data quality check completed (placeholder)"
    
    return 0
}

##
# Run all checks
##
run_all_checks() {
    log_info "${COMPONENT}: Starting all monitoring checks"
    
    local checks_passed=0
    local checks_failed=0
    
    # Health check
    if check_ingestion_health; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # Performance check
    if check_ingestion_performance; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # Data quality check
    if check_ingestion_data_quality; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    log_info "${COMPONENT}: Monitoring checks completed - passed: ${checks_passed}, failed: ${checks_failed}"
    
    if [[ ${checks_failed} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

##
# Main
##
main() {
    local check_type="all"
    # shellcheck disable=SC2034
    local verbose=false
    # shellcheck disable=SC2034
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -c|--check)
                check_type="${2}"
                shift 2
                ;;
            -v|--verbose)
                # shellcheck disable=SC2034
                verbose=true
                export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
                shift
                ;;
            -d|--dry-run)
                # shellcheck disable=SC2034
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "${COMPONENT}: Unknown option: ${1}"
                usage
                exit 1
                ;;
        esac
    done
    
    # Load configuration
    if ! load_all_configs; then
        log_error "${COMPONENT}: Failed to load configuration"
        exit 1
    fi
    
    # Validate configuration
    if ! validate_all_configs; then
        log_error "${COMPONENT}: Configuration validation failed"
        exit 1
    fi
    
    # Check if monitoring is enabled
    if [[ "${INGESTION_ENABLED:-true}" != "true" ]]; then
        log_info "${COMPONENT}: Monitoring disabled in configuration"
        exit 0
    fi
    
    log_info "${COMPONENT}: Starting ingestion monitoring"
    
    # Run requested check
    case "${check_type}" in
        health)
            if check_ingestion_health; then
                exit 0
            else
                exit 1
            fi
            ;;
        performance)
            if check_ingestion_performance; then
                exit 0
            else
                exit 1
            fi
            ;;
        data-quality)
            if check_ingestion_data_quality; then
                exit 0
            else
                exit 1
            fi
            ;;
        all)
            if run_all_checks; then
                exit 0
            else
                exit 1
            fi
            ;;
        *)
            log_error "${COMPONENT}: Unknown check type: ${check_type}"
            usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

