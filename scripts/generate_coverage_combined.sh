#!/usr/bin/env bash
#
# Generate Combined Coverage Report
# Shows both estimated and instrumented coverage side by side
#
# Version: 1.0.0
# Date: 2026-01-07
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Output directories
readonly COVERAGE_DIR="${PROJECT_ROOT}/coverage"
readonly COVERAGE_REPORT="${COVERAGE_DIR}/coverage_report_combined.txt"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Get estimated coverage for a script
##
get_estimated_coverage() {
    local script_path="${1}"
    local script_name
    script_name=$(basename "${script_path}" .sh)
    
    local test_count=0
    while IFS= read -r -d '' _; do
        test_count=$((test_count + 1))
    done < <(find "${PROJECT_ROOT}/tests" -name "*${script_name}*.sh" -type f -print0 2>/dev/null || true)
    
    if [[ ${test_count} -eq 0 ]]; then
        echo "0"
        return
    fi
    
    # Estimate coverage based on number of test files
    local coverage=0
    if [[ ${test_count} -ge 3 ]]; then
        coverage=80
    elif [[ ${test_count} -eq 2 ]]; then
        coverage=60
    elif [[ ${test_count} -eq 1 ]]; then
        coverage=40
    fi
    
    echo "${coverage}"
}

##
# Get instrumented coverage for a script
##
get_instrumented_coverage() {
    local script_path="${1}"
    local resultset_file="${COVERAGE_DIR}/.resultset.json"
    
    if [[ ! -f "${resultset_file}" ]]; then
        echo "N/A"
        return
    fi
    
    local coverage
    coverage=$(python3 -c "
import json
import sys
import os

try:
    script_path = '${script_path}'
    script_basename = os.path.basename(script_path)
    script_abs_path = os.path.abspath(script_path)
    
    with open('${resultset_file}', 'r') as f:
        data = json.load(f)
    
    for cmd_name, cmd_data in data.items():
        if 'coverage' in cmd_data:
            files = cmd_data['coverage']
            for file_path, coverage_data in files.items():
                file_basename = os.path.basename(file_path)
                if (script_path in file_path or 
                    script_abs_path in file_path or 
                    script_basename == script_basename):
                    if isinstance(coverage_data, list):
                        covered = sum(1 for x in coverage_data if x is not None and x > 0)
                        total = len([x for x in coverage_data if x is not None])
                        if total > 0:
                            percent = int((covered / total) * 100)
                            print(percent)
                            sys.exit(0)
    
    print(0)
except Exception:
    print(0)
" 2>/dev/null || echo "0")
    
    if [[ "${coverage}" == "0" ]]; then
        echo "0"
    else
        echo "${coverage}"
    fi
}

##
# Generate combined report
##
generate_combined_report() {
    print_message "${BLUE}" "Generating combined coverage report..."
    
    # Check if instrumented coverage exists
    local has_instrumented=false
    if [[ -f "${COVERAGE_DIR}/.resultset.json" ]]; then
        has_instrumented=true
    fi
    
    # Find all scripts
    local scripts=()
    while IFS= read -r -d '' script; do
        scripts+=("${script}")
    done < <(find "${PROJECT_ROOT}/bin" -name "*.sh" -type f -print0 | sort -z)
    
    {
        echo "OSM Notes Monitoring - Combined Coverage Report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
        echo ""
        echo "Coverage Target: >80%"
        echo ""
        echo "Understanding the Reports:"
        echo "  Estimated: Based on test file presence (fast, optimistic)"
        echo "  Instrumented: Based on lines actually executed (slow, accurate)"
        echo ""
        echo "Script Coverage Comparison:"
        echo "----------------------------------------"
        if [[ "${has_instrumented}" == "true" ]]; then
            printf "%-40s %12s %12s %10s\n" "Script" "Estimated" "Instrumented" "Gap"
            echo "----------------------------------------"
        else
            printf "%-40s %12s %12s\n" "Script" "Estimated" "Instrumented"
            echo "----------------------------------------"
            echo ""
            echo "Note: Instrumented coverage not available."
            echo "      Run: bash scripts/generate_coverage_instrumented_optimized.sh"
            echo ""
        fi
        
        local scripts_with_tests=0
        local scripts_above_threshold_est=0
        local scripts_above_threshold_inst=0
        local total_est=0
        local total_inst=0
        local est_count=0
        local inst_count=0
        
        for script in "${scripts[@]}"; do
            local script_name
            script_name=$(basename "${script}" .sh)
            
            local est_coverage
            est_coverage=$(get_estimated_coverage "${script}")
            local inst_coverage="N/A"
            
            if [[ "${has_instrumented}" == "true" ]]; then
                inst_coverage=$(get_instrumented_coverage "${script}")
            fi
            
            if [[ "${est_coverage}" != "0" ]]; then
                scripts_with_tests=$((scripts_with_tests + 1))
                total_est=$((total_est + est_coverage))
                est_count=$((est_count + 1))
                
                if [[ ${est_coverage} -ge 80 ]]; then
                    scripts_above_threshold_est=$((scripts_above_threshold_est + 1))
                fi
            fi
            
            if [[ "${inst_coverage}" != "N/A" ]] && [[ "${inst_coverage}" =~ ^[0-9]+$ ]]; then
                if [[ ${inst_coverage} -gt 0 ]]; then
                    total_inst=$((total_inst + inst_coverage))
                    inst_count=$((inst_count + 1))
                    
                    if [[ ${inst_coverage} -ge 80 ]]; then
                        scripts_above_threshold_inst=$((scripts_above_threshold_inst + 1))
                    fi
                fi
            fi
            
            # Calculate gap
            local gap=""
            if [[ "${has_instrumented}" == "true" ]] && [[ "${est_coverage}" =~ ^[0-9]+$ ]] && [[ "${inst_coverage}" =~ ^[0-9]+$ ]]; then
                local gap_value=$((est_coverage - inst_coverage))
                if [[ ${gap_value} -gt 0 ]]; then
                    gap="+${gap_value}%"
                elif [[ ${gap_value} -lt 0 ]]; then
                    gap="${gap_value}%"
                else
                    gap="0%"
                fi
            fi
            
            # Format output
            if [[ "${has_instrumented}" == "true" ]]; then
                printf "%-40s %10s%% %10s%% %10s\n" "${script_name}" "${est_coverage}" "${inst_coverage}" "${gap}"
            else
                printf "%-40s %10s%% %10s\n" "${script_name}" "${est_coverage}" "${inst_coverage}"
            fi
        done
        
        echo "----------------------------------------"
        echo ""
        echo "Summary:"
        echo "  Total scripts: ${#scripts[@]}"
        echo "  Scripts with tests: ${scripts_with_tests}"
        
        if [[ ${est_count} -gt 0 ]]; then
            local avg_est=$((total_est / est_count))
            echo "  Average estimated coverage: ${avg_est}%"
            echo "  Scripts above 80% (estimated): ${scripts_above_threshold_est}"
        fi
        
        if [[ "${has_instrumented}" == "true" ]] && [[ ${inst_count} -gt 0 ]]; then
            local avg_inst=$((total_inst / inst_count))
            echo "  Average instrumented coverage: ${avg_inst}%"
            echo "  Scripts above 80% (instrumented): ${scripts_above_threshold_inst}"
            echo ""
            echo "  Coverage gap: $((avg_est - avg_inst))% (estimated - instrumented)"
            echo ""
            echo "  Interpretation:"
            echo "    - Large gap indicates tests exist but don't execute much code"
            echo "    - Common causes: unit tests with mocks, conditional code paths"
            echo "    - Solution: Add integration tests or reduce mocks"
        fi
        
        echo ""
        echo "Detailed reports:"
        echo "  Estimated: ${COVERAGE_DIR}/coverage_report.txt"
        if [[ "${has_instrumented}" == "true" ]]; then
            echo "  Instrumented: ${COVERAGE_DIR}/coverage_report_instrumented.txt"
        else
            echo "  Instrumented: Run bash scripts/generate_coverage_instrumented_optimized.sh"
        fi
        echo ""
        echo "For more information, see: docs/COVERAGE_EXPLANATION.md"
    } > "${COVERAGE_REPORT}"
    
    print_message "${GREEN}" "✓ Combined coverage report generated: ${COVERAGE_REPORT}"
    
    # Display summary
    tail -30 "${COVERAGE_REPORT}"
}

##
# Main
##
main() {
    cd "${PROJECT_ROOT}" || exit 1
    
    print_message "${GREEN}" "OSM Notes Monitoring - Combined Coverage Report Generator"
    echo
    
    generate_combined_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
