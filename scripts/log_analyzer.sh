#!/usr/bin/env bash
#
# Log Analysis Utility
# Analyzes logs and generates statistics and reports
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
Log Analysis Utility

Analyzes logs and generates statistics and reports.

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    stats              Show log statistics (default)
    errors             Show error summary
    top-errors         Show top error messages
    timeline           Show log timeline
    components         Show component statistics
    summary            Show summary report

Options:
    -d, --dir DIR      Log directory (default: /var/log/osm-notes-monitoring)
    -s, --since TIME   Analyze logs since time
    -u, --until TIME   Analyze logs until time
    -c, --component NAME  Filter by component
    -o, --output FILE  Output to file
    -h, --help         Show this help message

Examples:
    # Show statistics
    $0 stats

    # Show error summary
    $0 errors

    # Show top errors
    $0 top-errors

    # Analyze last hour
    $0 --since "1 hour ago" stats

    # Component-specific analysis
    $0 --component ingestion errors

EOF
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
# Count log entries by level
##
count_by_level() {
    local log_file="${1}"
    local level="${2}"

    grep -cE "\[${level}\]" "${log_file}" 2>/dev/null || echo "0"
}

##
# Show statistics
##
show_stats() {
    local log_dir="${1}"
    local since="${2:-}"
    local until="${3:-}"
    local component="${4:-}"

    print_message "${BLUE}" "=== Log Statistics ==="
    echo

    local log_files
    mapfile -t log_files < <(get_log_files "${log_dir}")

    if [[ ${#log_files[@]} -eq 0 ]]; then
        print_message "${YELLOW}" "No log files found"
        return 1
    fi

    local total_lines=0
    local total_debug=0
    local total_info=0
    local total_warning=0
    local total_error=0

    for log_file in "${log_files[@]}"; do
        local filename
        filename=$(basename "${log_file}")

        # Filter by component if specified
        if [[ -n "${component}" ]] && ! echo "${filename}" | grep -qi "${component}"; then
            continue
        fi

        local lines
        lines=$(wc -l < "${log_file}" 2>/dev/null || echo "0")
        local debug
        debug=$(count_by_level "${log_file}" "DEBUG")
        local info
        info=$(count_by_level "${log_file}" "INFO")
        local warning
        warning=$(count_by_level "${log_file}" "WARNING")
        local error
        error=$(count_by_level "${log_file}" "ERROR")

        total_lines=$((total_lines + lines))
        total_debug=$((total_debug + debug))
        total_info=$((total_info + info))
        total_warning=$((total_warning + warning))
        total_error=$((total_error + error))

        printf "%-30s: Lines=%6d  DEBUG=%4d  INFO=%5d  WARNING=%4d  ERROR=%4d\n" \
            "${filename}" "${lines}" "${debug}" "${info}" "${warning}" "${error}"
    done

    echo
    print_message "${BLUE}" "=== Totals ==="
    printf "Total Lines:   %d\n" "${total_lines}"
    printf "DEBUG:         %d\n" "${total_debug}"
    printf "INFO:          %d\n" "${total_info}"
    printf "WARNING:       %d\n" "${total_warning}"
    printf "ERROR:         %d\n" "${total_error}"
}

##
# Show error summary
##
show_errors() {
    local log_dir="${1}"
    local since="${2:-}"
    local until="${3:-}"
    local component="${4:-}"

    print_message "${BLUE}" "=== Error Summary ==="
    echo

    local log_files
    mapfile -t log_files < <(get_log_files "${log_dir}")

    local error_count=0

    for log_file in "${log_files[@]}"; do
        local filename
        filename=$(basename "${log_file}")

        if [[ -n "${component}" ]] && ! echo "${filename}" | grep -qi "${component}"; then
            continue
        fi

        local errors
        mapfile -t errors < <(grep -E "\[ERROR\]" "${log_file}" 2>/dev/null || true)

        if [[ ${#errors[@]} -gt 0 ]]; then
            print_message "${YELLOW}" "File: ${filename} (${#errors[@]} errors)"
            for error in "${errors[@]}"; do
                echo "  ${error}"
            done
            echo
            error_count=$((error_count + ${#errors[@]}))
        fi
    done

    if [[ ${error_count} -eq 0 ]]; then
        print_message "${GREEN}" "No errors found"
    else
        print_message "${RED}" "Total errors: ${error_count}"
    fi
}

##
# Show top error messages
##
show_top_errors() {
    local log_dir="${1}"
    local top_n="${2:-10}"

    print_message "${BLUE}" "=== Top ${top_n} Error Messages ==="
    echo

    local log_files
    mapfile -t log_files < <(get_log_files "${log_dir}")

    # Extract error messages and count occurrences
    grep -hE "\[ERROR\]" "${log_files[@]}" 2>/dev/null | \
        sed 's/.*\[ERROR\][^:]*: //' | \
        sort | uniq -c | sort -rn | head -n "${top_n}" | \
        while read -r count message; do
            printf "%-6d %s\n" "${count}" "${message}"
        done
}

##
# Show component statistics
##
show_components() {
    local log_dir="${1}"

    print_message "${BLUE}" "=== Component Statistics ==="
    echo

    local log_files
    mapfile -t log_files < <(get_log_files "${log_dir}")

    declare -A component_stats

    for log_file in "${log_files[@]}"; do
        local filename
        filename=$(basename "${log_file}" .log)

        local error_count
        error_count=$(count_by_level "${log_file}" "ERROR")
        local warning_count
        warning_count=$(count_by_level "${log_file}" "WARNING")

        component_stats["${filename}_errors"]=$((component_stats["${filename}_errors"] + error_count))
        component_stats["${filename}_warnings"]=$((component_stats["${filename}_warnings"] + warning_count))
    done

    printf "%-30s %10s %10s\n" "Component" "Errors" "Warnings"
    echo "------------------------------------------------------------"

    for key in "${!component_stats[@]}"; do
        if [[ "${key}" =~ _errors$ ]]; then
            local component="${key%_errors}"
            # shellcheck disable=SC2178
            local errors="${component_stats[${key}]:-0}"
            local warnings_key="${component}_warnings"
            # shellcheck disable=SC2178
            local warnings="${component_stats[${warnings_key}]:-0}"
            # shellcheck disable=SC2128
            printf "%-30s %10d %10d\n" "${component}" "${errors}" "${warnings}"
        fi
    done
}

##
# Show summary report
##
show_summary() {
    local log_dir="${1}"

    print_message "${GREEN}" "=== Log Analysis Summary ==="
    echo

    show_stats "${log_dir}"
    echo
    show_components "${log_dir}"
    echo
    show_top_errors "${log_dir}" 5
}

##
# Main
##
main() {
    local log_dir="${LOG_DIR}"
    local command="stats"
    local since=""
    local until=""
    local component=""
    local output=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -d|--dir)
                log_dir="${2}"
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
            -c|--component)
                component="${2}"
                shift 2
                ;;
            -o|--output)
                output="${2}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            stats|errors|top-errors|timeline|components|summary)
                command="${1}"
                shift
                ;;
            *)
                print_message "${RED}" "Unknown option: ${1}"
                usage
                exit 1
                ;;
        esac
    done

    # Execute command
    case "${command}" in
        stats)
            if [[ -n "${output}" ]]; then
                show_stats "${log_dir}" "${since}" "${until}" "${component}" > "${output}"
            else
                show_stats "${log_dir}" "${since}" "${until}" "${component}"
            fi
            ;;
        errors)
            if [[ -n "${output}" ]]; then
                show_errors "${log_dir}" "${since}" "${until}" "${component}" > "${output}"
            else
                show_errors "${log_dir}" "${since}" "${until}" "${component}"
            fi
            ;;
        top-errors)
            if [[ -n "${output}" ]]; then
                show_top_errors "${log_dir}" 10 > "${output}"
            else
                show_top_errors "${log_dir}" 10
            fi
            ;;
        components)
            if [[ -n "${output}" ]]; then
                show_components "${log_dir}" > "${output}"
            else
                show_components "${log_dir}"
            fi
            ;;
        summary)
            if [[ -n "${output}" ]]; then
                show_summary "${log_dir}" > "${output}"
            else
                show_summary "${log_dir}"
            fi
            ;;
        *)
            print_message "${RED}" "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

