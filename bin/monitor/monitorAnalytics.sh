#!/usr/bin/env bash
#
# Analytics Monitoring Script
# Monitors the OSM-Notes-Analytics component health and performance
#
# Version: 1.0.0
# Date: 2025-12-26
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

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging
init_logging "${LOG_DIR}/analytics.log" "monitorAnalytics"

# Component name
readonly COMPONENT="ANALYTICS"

##
# Show usage
##
usage() {
    cat << EOF
Analytics Monitoring Script

Monitors the OSM-Notes-Analytics component for health, performance, and data quality.

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
    etl-status      Check ETL job execution status
    data-freshness  Check data warehouse freshness
    storage         Check storage growth
    query-performance Check query performance
    all             Run all checks (default)

Examples:
    # Run all checks
    $0

    # Run only health check
    $0 --check health

    # Run ETL status check
    $0 --check etl-status

    # Dry run (no database writes)
    $0 --dry-run

EOF
}

##
# Check ETL job execution status
##
check_etl_job_execution_status() {
    log_info "${COMPONENT}: Starting ETL job execution status check"
    
    # Check if analytics repository path is configured
    if [[ -z "${ANALYTICS_REPO_PATH:-}" ]]; then
        log_warning "${COMPONENT}: ANALYTICS_REPO_PATH not configured, skipping ETL job status check"
        return 0
    fi
    
    # Expected ETL scripts/jobs
    local etl_scripts=(
        "etl_main.sh"
        "etl_daily.sh"
        "etl_hourly.sh"
        "load_data.sh"
        "transform_data.sh"
    )
    
    local scripts_dir="${ANALYTICS_REPO_PATH}/bin"
    local scripts_found=0
    local scripts_executable=0
    local scripts_running=0
    local last_execution_timestamp=""
    local last_execution_age_seconds=0
    
    # Check each ETL script
    for script_name in "${etl_scripts[@]}"; do
        local script_path="${scripts_dir}/${script_name}"
        
        # Check if script exists
        if [[ ! -f "${script_path}" ]]; then
            log_debug "${COMPONENT}: ETL script not found: ${script_name}"
            continue
        fi
        
        scripts_found=$((scripts_found + 1))
        
        # Check if script is executable
        if [[ -x "${script_path}" ]]; then
            scripts_executable=$((scripts_executable + 1))
        else
            log_warning "${COMPONENT}: ETL script exists but not executable: ${script_name}"
        fi
        
        # Check if script process is running
        local script_basename
        script_basename=$(basename "${script_path}")
        if pgrep -f "${script_basename}" > /dev/null 2>&1; then
            scripts_running=$((scripts_running + 1))
            log_info "${COMPONENT}: ETL script is running: ${script_name}"
            
            # Get process info
            local pid
            pid=$(pgrep -f "${script_basename}" | head -1)
            local runtime
            runtime=$(ps -o etime= -p "${pid}" 2>/dev/null | tr -d ' ' || echo "unknown")
            log_debug "${COMPONENT}: ETL script ${script_name} PID: ${pid}, Runtime: ${runtime}"
        fi
    done
    
    # Record metrics
    record_metric "${COMPONENT}" "etl_scripts_found" "${scripts_found}" "component=analytics"
    record_metric "${COMPONENT}" "etl_scripts_executable" "${scripts_executable}" "component=analytics"
    record_metric "${COMPONENT}" "etl_scripts_running" "${scripts_running}" "component=analytics"
    
    # Check for alerts
    local scripts_found_threshold="${ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD:-2}"
    if [[ ${scripts_found} -lt ${scripts_found_threshold} ]]; then
        log_warning "${COMPONENT}: Low number of ETL scripts found: ${scripts_found} (threshold: ${scripts_found_threshold})"
        send_alert "WARNING" "${COMPONENT}" "Low number of ETL scripts found: ${scripts_found} (threshold: ${scripts_found_threshold})"
    fi
    
    if [[ ${scripts_executable} -lt ${scripts_found} ]]; then
        log_warning "${COMPONENT}: Some ETL scripts are not executable: ${scripts_executable}/${scripts_found}"
        send_alert "WARNING" "${COMPONENT}" "ETL scripts executable count (${scripts_executable}) is less than scripts found (${scripts_found})"
    fi
    
    # Check last execution timestamp from logs
    local log_dir="${ANALYTICS_LOG_DIR:-${ANALYTICS_REPO_PATH}/logs}"
    if [[ -d "${log_dir}" ]]; then
        # Find most recent log file
        local latest_log
        latest_log=$(find "${log_dir}" -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        
        if [[ -n "${latest_log}" ]] && [[ -f "${latest_log}" ]]; then
            # Get last modification time
            if command -v stat > /dev/null 2>&1; then
                # Try to get modification time (works on Linux and macOS with different flags)
                if stat -c %Y "${latest_log}" > /dev/null 2>&1; then
                    # Linux
                    last_execution_timestamp=$(stat -c %Y "${latest_log}")
                elif stat -f %m "${latest_log}" > /dev/null 2>&1; then
                    # macOS
                    last_execution_timestamp=$(stat -f %m "${latest_log}")
                fi
                
                if [[ -n "${last_execution_timestamp}" ]]; then
                    local current_timestamp
                    current_timestamp=$(date +%s)
                    last_execution_age_seconds=$((current_timestamp - last_execution_timestamp))
                    
                    # Record metric
                    record_metric "${COMPONENT}" "last_etl_execution_age_seconds" "${last_execution_age_seconds}" "component=analytics"
                    
                    # Check threshold
                    local freshness_threshold="${ANALYTICS_DATA_FRESHNESS_THRESHOLD:-3600}"
                    if [[ ${last_execution_age_seconds} -gt ${freshness_threshold} ]]; then
                        log_warning "${COMPONENT}: Last ETL execution is ${last_execution_age_seconds}s old (threshold: ${freshness_threshold}s)"
                        send_alert "WARNING" "${COMPONENT}" "Last ETL execution is ${last_execution_age_seconds}s old (threshold: ${freshness_threshold}s)"
                    fi
                fi
            fi
        else
            log_debug "${COMPONENT}: No log files found in ${log_dir}"
        fi
    else
        log_debug "${COMPONENT}: Log directory not found: ${log_dir}"
    fi
    
    # Check for ETL job failures in logs (last 24 hours)
    if [[ -d "${log_dir}" ]]; then
        local error_count=0
        local failure_count=0
        
        # Count errors and failures in recent logs
        if find "${log_dir}" -name "*.log" -type f -mtime -1 -exec grep -l -i "error\|failed\|failure" {} \; 2>/dev/null | head -10 | while read -r logfile; do
            local file_errors
            file_errors=$(grep -ic "error" "${logfile}" 2>/dev/null || echo "0")
            local file_failures
            file_failures=$(grep -ic -E "failed|failure" "${logfile}" 2>/dev/null || echo "0")
            error_count=$((error_count + file_errors))
            failure_count=$((failure_count + file_failures))
        done; then
            # Record metrics
            if [[ ${error_count} -gt 0 ]]; then
                record_metric "${COMPONENT}" "etl_error_count" "${error_count}" "component=analytics,period=24h"
            fi
            if [[ ${failure_count} -gt 0 ]]; then
                record_metric "${COMPONENT}" "etl_failure_count" "${failure_count}" "component=analytics,period=24h"
                
                # Alert on failures
                send_alert "WARNING" "${COMPONENT}" "ETL job failures detected: ${failure_count} failures in last 24 hours"
            fi
        fi
    fi
    
    log_info "${COMPONENT}: ETL job execution status check completed - scripts found: ${scripts_found}, running: ${scripts_running}"
    
    return 0
}

##
# Check data warehouse freshness
##
check_data_warehouse_freshness() {
    log_info "${COMPONENT}: Starting data warehouse freshness check"
    
    # TODO: Implement data warehouse freshness check
    # This should check:
    # - Time since last data update
    # - Data freshness by table/mart
    # - Stale data detection
    
    log_debug "${COMPONENT}: Data warehouse freshness check not yet implemented"
    
    return 0
}

##
# Check ETL processing duration
##
check_etl_processing_duration() {
    log_info "${COMPONENT}: Starting ETL processing duration check"
    
    # TODO: Implement ETL processing duration check
    # This should check:
    # - Average ETL processing duration
    # - Long-running ETL jobs
    # - Duration trends
    
    log_debug "${COMPONENT}: ETL processing duration check not yet implemented"
    
    return 0
}

##
# Check data mart update status
##
check_data_mart_update_status() {
    log_info "${COMPONENT}: Starting data mart update status check"
    
    # TODO: Implement data mart update status check
    # This should check:
    # - Data mart update timestamps
    # - Update success/failure status
    # - Update frequency
    
    log_debug "${COMPONENT}: Data mart update status check not yet implemented"
    
    return 0
}

##
# Check query performance
##
check_query_performance() {
    log_info "${COMPONENT}: Starting query performance check"
    
    # TODO: Implement query performance check
    # This should check:
    # - Slow queries
    # - Query execution times
    # - Query frequency
    # - Index usage
    
    log_debug "${COMPONENT}: Query performance check not yet implemented"
    
    return 0
}

##
# Check storage growth
##
check_storage_growth() {
    log_info "${COMPONENT}: Starting storage growth check"
    
    # TODO: Implement storage growth check
    # This should check:
    # - Database size
    # - Table sizes
    # - Growth rate
    # - Storage capacity
    
    log_debug "${COMPONENT}: Storage growth check not yet implemented"
    
    return 0
}

##
# Check data quality in DWH
##
check_data_quality() {
    log_info "${COMPONENT}: Starting data quality check"
    
    # TODO: Implement data quality check
    # This should check:
    # - Data completeness
    # - Data consistency
    # - Data validation results
    # - Data quality scores
    
    log_debug "${COMPONENT}: Data quality check not yet implemented"
    
    return 0
}

##
# Check component health status
##
check_health_status() {
    log_info "${COMPONENT}: Starting health status check"
    
    # Check database connection
    if ! check_database_connection; then
        log_error "${COMPONENT}: Database connection failed"
        send_alert "CRITICAL" "${COMPONENT}" "Database connection failed"
        return 1
    fi
    
    # Check if analytics database is accessible
    # TODO: Add specific analytics database connection check
    
    log_info "${COMPONENT}: Health check passed"
    return 0
}

##
# Check performance metrics
##
check_performance() {
    log_info "${COMPONENT}: Starting performance checks"
    
    check_etl_processing_duration
    check_query_performance
    check_storage_growth
    
    return 0
}

##
# Check data quality metrics
##
check_data_quality_metrics() {
    log_info "${COMPONENT}: Starting data quality checks"
    
    check_data_warehouse_freshness
    check_data_quality
    
    return 0
}

##
# Run all checks
##
run_all_checks() {
    log_info "${COMPONENT}: Running all monitoring checks"
    
    check_health_status
    check_etl_job_execution_status
    check_data_warehouse_freshness
    check_etl_processing_duration
    check_data_mart_update_status
    check_query_performance
    check_storage_growth
    check_data_quality
    
    return 0
}

##
# Main function
##
main() {
    local check_type="all"
    # shellcheck disable=SC2034
    local verbose=false
    # shellcheck disable=SC2034
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--check)
                check_type="${2:-all}"
                shift 2
                ;;
            -v|--verbose)
                # shellcheck disable=SC2034
                verbose=true
                shift
                ;;
            -d|--dry-run)
                # shellcheck disable=SC2034
                dry_run=true
                export DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set verbose logging if requested
    if [[ "${verbose}" == "true" ]]; then
        export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    fi
    
    # Load configuration
    if ! load_monitoring_config; then
        log_error "${COMPONENT}: Failed to load monitoring configuration"
        exit 1
    fi
    
    # Check if analytics monitoring is enabled
    if [[ "${ANALYTICS_ENABLED:-false}" != "true" ]]; then
        log_info "${COMPONENT}: Analytics monitoring is disabled"
        exit 0
    fi
    
    # Initialize alerting
    init_alerting
    
    # Run requested checks
    case "${check_type}" in
        health)
            check_health_status
            ;;
        performance)
            check_performance
            ;;
        data-quality)
            check_data_quality_metrics
            ;;
        etl-status)
            check_etl_job_execution_status
            ;;
        data-freshness)
            check_data_warehouse_freshness
            ;;
        storage)
            check_storage_growth
            ;;
        query-performance)
            check_query_performance
            ;;
        all)
            run_all_checks
            ;;
        *)
            log_error "Unknown check type: ${check_type}"
            usage
            exit 1
            ;;
    esac
    
    log_info "${COMPONENT}: Monitoring checks completed"
    return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

