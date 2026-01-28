#!/usr/bin/env bash
#
# Log Aggregation Utility
# Aggregates logs from multiple components into a single output
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

# Source libraries
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Default log directory
LOG_DIR="${LOG_DIR:-/var/log/osm-notes-monitoring}"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Show usage
##
usage() {
    cat << EOF
Log Aggregation Utility

Aggregates logs from multiple components into a single output with filtering options.

Usage: $0 [OPTIONS]

Options:
    -d, --dir DIR          Log directory (default: /var/log/osm-notes-monitoring)
    -c, --component NAME   Filter by component name
    -l, --level LEVEL      Filter by log level (DEBUG, INFO, WARNING, ERROR)
    -s, --since TIME       Show logs since time (e.g., "1 hour ago", "2025-12-24 10:00")
    -u, --until TIME       Show logs until time
    -g, --grep PATTERN     Search for pattern in logs
    -o, --output FILE      Output to file instead of stdout
    -f, --follow           Follow log files (like tail -f)
    -n, --lines N          Show last N lines (default: 100)
    -t, --tail             Show tail of logs (default behavior)
    -h, --help             Show this help message

Examples:
    # Show last 100 lines from all logs
    $0

    # Show only ERROR logs
    $0 --level ERROR

    # Show logs from ingestion component
    $0 --component ingestion

    # Show logs from last hour
    $0 --since "1 hour ago"

    # Search for "database" in logs
    $0 --grep database

    # Follow logs in real-time
    $0 --follow

    # Combine filters
    $0 --component ingestion --level ERROR --since "1 hour ago"

EOF
}

##
# Parse time string to epoch
##
parse_time() {
    local time_str="${1}"

    # Try date parsing
    if date -d "${time_str}" +%s 2>/dev/null; then
        return 0
    fi

    # Try relative time
    if date -d "now ${time_str}" +%s 2>/dev/null; then
        return 0
    fi

    # Try absolute date
    if date -d "${time_str}" +%s 2>/dev/null; then
        return 0
    fi

    return 1
}

##
# Filter logs by time
##
filter_by_time() {
    local since="${1:-}"
    local until="${2:-}"
    local file="${3}"

    if [[ -z "${since}" ]] && [[ -z "${until}" ]]; then
        cat "${file}"
        return 0
    fi

    local since_epoch=""
    local until_epoch=""

    if [[ -n "${since}" ]]; then
        since_epoch=$(parse_time "${since}" || echo "0")
    fi

    if [[ -n "${until}" ]]; then
        until_epoch=$(parse_time "${until}" || echo "9999999999")
    fi

    while IFS= read -r line; do
        # Extract timestamp from log line (format: YYYY-MM-DD HH:MM:SS)
        if [[ "${line}" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            local log_time="${BASH_REMATCH[1]}"
            local log_epoch
            log_epoch=$(date -d "${log_time}" +%s 2>/dev/null || echo "0")

            if [[ -n "${since_epoch}" ]] && [[ ${log_epoch} -lt ${since_epoch} ]]; then
                continue
            fi

            if [[ -n "${until_epoch}" ]] && [[ ${log_epoch} -gt ${until_epoch} ]]; then
                continue
            fi

            echo "${line}"
        else
            # If no timestamp, include line (might be continuation)
            echo "${line}"
        fi
    done < "${file}"
}

##
# Filter logs by level
##
filter_by_level() {
    local level="${1}"
    local file="${2}"

    if [[ -z "${level}" ]]; then
        cat "${file}"
        return 0
    fi

    grep -E "\[${level}\]" "${file}" || true
}

##
# Filter logs by component
##
filter_by_component() {
    local component="${1}"
    local file="${2}"

    if [[ -z "${component}" ]]; then
        cat "${file}"
        return 0
    fi

    grep -i "${component}" "${file}" || true
}

##
# Filter logs by pattern
##
filter_by_pattern() {
    local pattern="${1}"
    local file="${2}"

    if [[ -z "${pattern}" ]]; then
        cat "${file}"
        return 0
    fi

    grep -i "${pattern}" "${file}" || true
}

##
# Get log files
##
get_log_files() {
    local log_dir="${1}"

    if [[ ! -d "${log_dir}" ]]; then
        print_message "${YELLOW}" "Warning: Log directory does not exist: ${log_dir}"
        return 1
    fi

    find "${log_dir}" -name "*.log" -type f 2>/dev/null | sort
}

##
# Aggregate logs
##
aggregate_logs() {
    local log_dir="${1}"
    local component="${2:-}"
    local level="${3:-}"
    local since="${4:-}"
    local until="${5:-}"
    local pattern="${6:-}"
    local lines="${7:-100}"
    local follow="${8:-false}"

    local log_files
    mapfile -t log_files < <(get_log_files "${log_dir}")

    if [[ ${#log_files[@]} -eq 0 ]]; then
        print_message "${YELLOW}" "No log files found in ${log_dir}"
        return 1
    fi

    if [[ "${follow}" == "true" ]]; then
        # Follow mode - use tail -f
        print_message "${BLUE}" "Following logs (Ctrl+C to stop)..."
        tail -f "${log_files[@]}" 2>/dev/null | while IFS= read -r line; do
            local include=true

            if [[ -n "${component}" ]] && ! echo "${line}" | grep -qi "${component}"; then
                include=false
            fi

            if [[ "${include}" == "true" ]] && [[ -n "${level}" ]] && ! echo "${line}" | grep -qE "\[${level}\]"; then
                include=false
            fi

            if [[ "${include}" == "true" ]] && [[ -n "${pattern}" ]] && ! echo "${line}" | grep -qi "${pattern}"; then
                include=false
            fi

            if [[ "${include}" == "true" ]]; then
                echo "${line}"
            fi
        done
    else
        # Normal mode - aggregate and filter
        for log_file in "${log_files[@]}"; do
            # Apply filters
            filter_by_time "${since}" "${until}" "${log_file}" | \
                filter_by_level "${level}" - | \
                filter_by_component "${component}" - | \
                filter_by_pattern "${pattern}" -
        done | sort | tail -n "${lines}"
    fi
}

##
# Main
##
main() {
    local log_dir="${LOG_DIR}"
    local component=""
    local level=""
    local since=""
    local until=""
    local pattern=""
    local output=""
    local follow=false
    local lines=100

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -d|--dir)
                log_dir="${2}"
                shift 2
                ;;
            -c|--component)
                component="${2}"
                shift 2
                ;;
            -l|--level)
                level="${2}"
                shift 2
                ;;
            -s|--since)
                since="${2}"
                shift 2
                ;;
            -u|--until)
                until="${2}"
                shift 2
                ;;
            -g|--grep)
                pattern="${2}"
                shift 2
                ;;
            -o|--output)
                output="${2}"
                shift 2
                ;;
            -f|--follow)
                follow=true
                shift
                ;;
            -n|--lines)
                lines="${2}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_message "${RED}" "Unknown option: ${1}"
                usage
                exit 1
                ;;
        esac
    done

    # Validate level
    if [[ -n "${level}" ]]; then
        case "${level}" in
            DEBUG|INFO|WARNING|ERROR)
                ;;
            *)
                print_message "${RED}" "Invalid log level: ${level}"
                print_message "${YELLOW}" "Valid levels: DEBUG, INFO, WARNING, ERROR"
                exit 1
                ;;
        esac
    fi

    # Aggregate logs
    if [[ -n "${output}" ]]; then
        aggregate_logs "${log_dir}" "${component}" "${level}" "${since}" "${until}" "${pattern}" "${lines}" "${follow}" > "${output}"
        print_message "${GREEN}" "Logs written to: ${output}"
    else
        aggregate_logs "${log_dir}" "${component}" "${level}" "${since}" "${until}" "${pattern}" "${lines}" "${follow}"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

