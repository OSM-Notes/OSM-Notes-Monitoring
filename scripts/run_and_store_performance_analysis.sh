#!/usr/bin/env bash
#
# Performance Analysis Runner and Metrics Storage Script
# Executes analyzeDatabasePerformance.sh and stores detailed metrics in monitoring database
#
# This script is designed to be run monthly from the ingestion project's cron.
# It executes the resource-intensive analyzeDatabasePerformance.sh script and
# stores the results as metrics in the OSM-Notes-Monitoring database for trend tracking.
#
# Version: 1.0.0
# Date: 2026-01-09
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

# Source configuration
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
    source "${PROJECT_ROOT}/etc/properties.sh"
fi

# Source libraries
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh" ]]; then
    source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
fi
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh" ]]; then
    source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
fi
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh" ]]; then
    source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"
fi
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/bin/lib/configFunctions.sh" ]]; then
    source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
fi

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging
init_logging "${LOG_DIR}/performance_analysis.log" "performanceAnalysis"

# Component name
readonly COMPONENT="INGESTION"

##
# Show usage
##
usage() {
    cat << EOF
Performance Analysis Runner and Metrics Storage Script

Executes analyzeDatabasePerformance.sh from the ingestion project and stores
detailed metrics in the monitoring database for trend tracking.

Usage: $0 [OPTIONS]

Options:
    --ingestion-repo PATH    Path to OSM-Notes-Ingestion repository (required if --input-file not used)
    --monitoring-db DBNAME   Monitoring database name (default: from etc/properties.sh)
    --ingestion-db DBNAME    Ingestion database name (default: notes)
    --output-dir DIR         Directory to save output files (default: logs/performance_output)
    --input-file FILE        Parse existing output file instead of running script (for cron integration)
    --verbose                Enable verbose output
    -h, --help               Show this help message

Environment Variables:
    INGESTION_REPO_PATH      Path to OSM-Notes-Ingestion repository
    DBNAME                   Monitoring database name
    INGESTION_DBNAME         Ingestion database name
    DBHOST, DBPORT, DBUSER   Database connection parameters

Examples:
    # Run with ingestion repo path (executes script and stores metrics)
    $0 --ingestion-repo /path/to/OSM-Notes-Ingestion

    # Parse existing output file (for cron integration)
    $0 --input-file /home/notes/logs/db_performance_monthly_20260101.log

    # From cron - integrated with existing analyzeDatabasePerformance.sh execution
    # Note: In crontab, % must be escaped as \%
    # Example crontab entry (copy to crontab -e):
    # Format: 0 3 1 * * /path/to/analyzeDatabasePerformance.sh --db notes > /path/to/logs/db_performance_monthly_\$(date +\\%Y\\%m\\%d).log 2>&1 && \\
    #     /path/to/OSM-Notes-Monitoring/scripts/run_and_store_performance_analysis.sh \\
    #         --input-file /path/to/logs/db_performance_monthly_\$(date +\\%Y\\%m\\%d).log

EOF
}

##
# Parse command line arguments
##
parse_args() {
    INGESTION_REPO_PATH="${INGESTION_REPO_PATH:-}"
    MONITORING_DBNAME="${DBNAME:-osm_notes_monitoring}"
    INGESTION_DBNAME="${INGESTION_DBNAME:-notes}"
    OUTPUT_DIR="${LOG_DIR}/performance_output"
    INPUT_FILE=""
    VERBOSE=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ingestion-repo)
                INGESTION_REPO_PATH="$2"
                shift 2
                ;;
            --monitoring-db)
                MONITORING_DBNAME="$2"
                shift 2
                ;;
            --ingestion-db)
                INGESTION_DBNAME="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --input-file)
                INPUT_FILE="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE="true"
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
    
    # Validate required parameters
    if [[ -n "${INPUT_FILE}" ]]; then
        # If input file is provided, validate it exists
        if [[ ! -f "${INPUT_FILE}" ]]; then
            log_error "Input file not found: ${INPUT_FILE}"
            exit 1
        fi
        log_info "Using existing output file: ${INPUT_FILE}"
    elif [[ -z "${INGESTION_REPO_PATH}" ]]; then
        log_error "Either --ingestion-repo or --input-file is required"
        usage
        exit 1
    elif [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
        log_error "Ingestion repository not found: ${INGESTION_REPO_PATH}"
        exit 1
    fi
}

##
# Parse performance analysis output and extract metrics
##
parse_performance_output() {
    local output_file="${1:?Output file required}"
    local output
    
    if [[ ! -f "${output_file}" ]]; then
        log_warning "Output file not found: ${output_file}"
        return 1
    fi
    
    output=$(cat "${output_file}" 2>/dev/null || echo "")
    
    if [[ -z "${output}" ]]; then
        log_warning "Output file is empty: ${output_file}"
        return 1
    fi
    
    # Extract basic counts
    local pass_count
    pass_count=$(echo "${output}" | grep -cE "PASS|✓" || echo "0")
    local fail_count
    fail_count=$(echo "${output}" | grep -cE "FAIL|✗" || echo "0")
    local warning_count
    warning_count=$(echo "${output}" | grep -cE "WARNING|⚠" || echo "0")
    
    # Store basic metrics
    record_metric "${COMPONENT}" "performance_check_passes" "${pass_count}" "component=ingestion,check=analyzeDatabasePerformance,source=monthly_cron"
    record_metric "${COMPONENT}" "performance_check_failures" "${fail_count}" "component=ingestion,check=analyzeDatabasePerformance,source=monthly_cron"
    record_metric "${COMPONENT}" "performance_check_warnings" "${warning_count}" "component=ingestion,check=analyzeDatabasePerformance,source=monthly_cron"
    
    log_info "Parsed metrics: passes=${pass_count}, failures=${fail_count}, warnings=${warning_count}"
    
    # Try to extract more detailed metrics from output
    # Look for specific patterns that might indicate performance issues
    
    # Count different types of checks (if output has structured sections)
    local index_checks=0
    local query_checks=0
    local table_checks=0
    
    if echo "${output}" | grep -qi "index"; then
        index_checks=$(echo "${output}" | grep -ciE "index.*(PASS|FAIL|WARNING)" || echo "0")
    fi
    
    if echo "${output}" | grep -qi "query"; then
        query_checks=$(echo "${output}" | grep -ciE "query.*(PASS|FAIL|WARNING)" || echo "0")
    fi
    
    if echo "${output}" | grep -qi "table"; then
        table_checks=$(echo "${output}" | grep -ciE "table.*(PASS|FAIL|WARNING)" || echo "0")
    fi
    
    # Store detailed metrics if found
    if [[ ${index_checks} -gt 0 ]]; then
        record_metric "${COMPONENT}" "performance_check_index_checks" "${index_checks}" "component=ingestion,check=analyzeDatabasePerformance,type=index"
    fi
    
    if [[ ${query_checks} -gt 0 ]]; then
        record_metric "${COMPONENT}" "performance_check_query_checks" "${query_checks}" "component=ingestion,check=analyzeDatabasePerformance,type=query"
    fi
    
    if [[ ${table_checks} -gt 0 ]]; then
        record_metric "${COMPONENT}" "performance_check_table_checks" "${table_checks}" "component=ingestion,check=analyzeDatabasePerformance,type=table"
    fi
    
    # Store output file path in metadata for reference
    local output_file_metric
    output_file_metric=$(echo "${output_file}" | jq -R . 2>/dev/null || echo "\"${output_file}\"")
    record_metric "${COMPONENT}" "performance_check_output_file" "1" "component=ingestion,check=analyzeDatabasePerformance,output_file=${output_file_metric}"
    
    return 0
}

##
# Main execution
##
main() {
    log_info "Starting monthly performance analysis and metrics storage"
    
    # Parse arguments
    parse_args "$@"
    
    # Set monitoring database
    export DBNAME="${MONITORING_DBNAME}"
    
    # Set verbose logging if requested
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        export LOG_LEVEL="DEBUG"
        log_info "Verbose mode enabled"
    fi
    
    # Check database connection
    if ! check_database_connection; then
        log_error "Cannot connect to monitoring database: ${DBNAME}"
        exit 1
    fi
    
    local output_file
    local exit_code=0
    local duration=0
    
    # If input file is provided, parse it instead of running the script
    if [[ -n "${INPUT_FILE}" ]]; then
        log_info "Parsing existing output file: ${INPUT_FILE}"
        output_file="${INPUT_FILE}"
        
        # Try to determine exit code from file (check for error patterns)
        if grep -qiE "ERROR|FAIL|exit code|timed out" "${INPUT_FILE}" 2>/dev/null; then
            exit_code=1
        else
            exit_code=0
        fi
        
        # Try to extract duration from file if available
        local duration_match
        duration_match=$(grep -iE "duration|took.*seconds?" "${INPUT_FILE}" 2>/dev/null | head -1 || echo "")
        if [[ -n "${duration_match}" ]]; then
            # Try to extract number of seconds
            duration=$(echo "${duration_match}" | grep -oE "[0-9]+" | head -1 || echo "0")
        fi
        
        log_info "Using existing output file, exit_code=${exit_code}, duration=${duration}s"
    else
        # Path to analyzeDatabasePerformance.sh
        local perf_script="${INGESTION_REPO_PATH}/bin/monitor/analyzeDatabasePerformance.sh"
        
        if [[ ! -f "${perf_script}" ]]; then
            log_error "analyzeDatabasePerformance.sh not found: ${perf_script}"
            exit 1
        fi
        
        if [[ ! -x "${perf_script}" ]]; then
            log_info "Making script executable: ${perf_script}"
            chmod +x "${perf_script}" || {
                log_error "Cannot make script executable: ${perf_script}"
                exit 1
            }
        fi
        
        # Create output directory
        mkdir -p "${OUTPUT_DIR}"
        
        # Set up output file
        output_file="${OUTPUT_DIR}/analyzeDatabasePerformance_$(date +%Y%m%d_%H%M%S).txt"
        
        # Export database connection variables for the script
        export DBHOST="${INGESTION_DBHOST:-${DBHOST:-localhost}}"
        export DBPORT="${INGESTION_DBPORT:-${DBPORT:-5432}}"
        export DBUSER="${INGESTION_DBUSER:-${DBUSER:-postgres}}"
        export DBNAME="${INGESTION_DBNAME}"
        
        log_info "Running analyzeDatabasePerformance.sh from ${perf_script}"
        log_info "Output will be saved to: ${output_file}"
        log_info "Metrics will be stored in monitoring database: ${MONITORING_DBNAME}"
        
        # Record start time
        local start_time
        start_time=$(date +%s)
        
        # Execute the performance analysis script
        local output
        
        # Set timeout (default: 1 hour for monthly execution)
        local timeout_seconds="${PERFORMANCE_ANALYSIS_TIMEOUT:-3600}"
        
        if command -v timeout >/dev/null 2>&1; then
            if ! output=$(cd "${INGESTION_REPO_PATH}" && timeout "${timeout_seconds}" bash "${perf_script}" --db "${INGESTION_DBNAME}" 2>&1 | tee "${output_file}"); then
                exit_code=$?
                if [[ ${exit_code} -eq 124 ]]; then
                    log_error "Script execution timed out after ${timeout_seconds}s"
                    echo "ERROR: Script execution timed out after ${timeout_seconds} seconds" >> "${output_file}"
                fi
            fi
        else
            log_warning "timeout command not available, running without timeout"
            if ! output=$(cd "${INGESTION_REPO_PATH}" && bash "${perf_script}" --db "${INGESTION_DBNAME}" 2>&1 | tee "${output_file}"); then
                exit_code=$?
            fi
        fi
        
        # Calculate duration
        local end_time
        end_time=$(date +%s)
        duration=$((end_time - start_time))
    fi
    
    # Store execution status and duration
    if [[ ${exit_code} -eq 0 ]]; then
        record_metric "${COMPONENT}" "performance_check_status" "1" "component=ingestion,check=analyzeDatabasePerformance,source=monthly_cron"
        log_info "Performance analysis completed successfully (duration: ${duration}s)"
    else
        record_metric "${COMPONENT}" "performance_check_status" "0" "component=ingestion,check=analyzeDatabasePerformance,source=monthly_cron,exit_code=${exit_code}"
        log_error "Performance analysis failed with exit code ${exit_code} (duration: ${duration}s)"
    fi
    
    record_metric "${COMPONENT}" "performance_check_duration" "${duration}" "component=ingestion,check=analyzeDatabasePerformance,source=monthly_cron"
    
    # Parse output and store detailed metrics
    if [[ ${exit_code} -eq 0 ]]; then
        log_info "Parsing output and storing detailed metrics"
        if parse_performance_output "${output_file}"; then
            log_info "Metrics stored successfully"
        else
            log_warning "Failed to parse some metrics from output"
        fi
    else
        log_warning "Skipping metric parsing due to script failure"
    fi
    
    # Clean up old output files (keep last 12 months)
    log_info "Cleaning up old output files (keeping last 12 months)"
    find "${OUTPUT_DIR}" -name "analyzeDatabasePerformance_*.txt" -type f -mtime +365 -delete 2>/dev/null || true
    
    log_info "Performance analysis and metrics storage completed"
    
    return ${exit_code}
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
