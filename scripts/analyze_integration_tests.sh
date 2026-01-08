#!/usr/bin/env bash
#
# Analyze Integration Tests Performance
# Measures execution time and identifies slow tests
#
# Version: 1.0.0
# Date: 2026-01-07
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Thresholds (in seconds)
readonly FAST_THRESHOLD=5
readonly MEDIUM_THRESHOLD=15
readonly SLOW_THRESHOLD=30

# Output file
readonly ANALYSIS_FILE="${PROJECT_ROOT}/coverage/integration_tests_analysis.txt"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Analyze a single test file
##
analyze_test_file() {
    local test_file="${1}"
    local test_name
    test_name=$(basename "${test_file}")
    
    print_message "${BLUE}" "Analyzing: ${test_name}..."
    
    # Count tests
    local test_count
    test_count=$(grep -c "^@test" "${test_file}" 2>/dev/null || echo "0")
    
    # Count sleeps and waits
    local sleep_count
    sleep_count=$(grep -c "sleep\|wait" "${test_file}" 2>/dev/null || echo "0")
    
    # Check if uses database
    local uses_db=false
    if grep -q "skip_if_database_not_available\|check_database_connection\|psql\|execute_sql_query" "${test_file}" 2>/dev/null; then
        uses_db=true
    fi
    
    # Check if executes scripts directly
    local executes_scripts=false
    if grep -q "bash.*bin/\|run bash\|\./bin/" "${test_file}" 2>/dev/null; then
        executes_scripts=true
    fi
    
    # Check if calls main()
    local calls_main=false
    if grep -q "run main\|main\s" "${test_file}" 2>/dev/null; then
        calls_main=true
    fi
    
    # Measure execution time (with timeout)
    local start_time
    start_time=$(date +%s.%N)
    
    # Run test with timeout (30 seconds max per test file)
    local timeout_result=0
    timeout 30 bats "${test_file}" >/dev/null 2>&1 || timeout_result=$?
    
    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "${end_time} - ${start_time}" | bc 2>/dev/null || echo "0")
    duration=$(printf "%.2f" "${duration}" 2>/dev/null || echo "0")
    
    # Determine category
    local category="fast"
    if (( $(echo "${duration} > ${SLOW_THRESHOLD}" | bc -l 2>/dev/null || echo 0) )); then
        category="very_slow"
    elif (( $(echo "${duration} > ${MEDIUM_THRESHOLD}" | bc -l 2>/dev/null || echo 0) )); then
        category="slow"
    elif (( $(echo "${duration} > ${FAST_THRESHOLD}" | bc -l 2>/dev/null || echo 0) )); then
        category="medium"
    fi
    
    # Output results
    echo "${test_name}|${test_count}|${sleep_count}|${uses_db}|${executes_scripts}|${calls_main}|${duration}|${category}|${timeout_result}"
}

##
# Main
##
main() {
    print_message "${GREEN}" "Integration Tests Performance Analysis"
    echo
    
    # Create output directory
    mkdir -p "${PROJECT_ROOT}/coverage"
    
    # Find all integration test files
    local test_files=()
    while IFS= read -r -d '' test_file; do
        test_files+=("${test_file}")
    done < <(find "${PROJECT_ROOT}/tests/integration" -name "*.sh" -type f -print0 2>/dev/null | sort -z)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        print_message "${YELLOW}" "No integration tests found"
        return 0
    fi
    
    print_message "${BLUE}" "Found ${#test_files[@]} integration test files"
    echo
    
    # Analyze each test
    {
        echo "Test File|Tests|Sleeps|Uses DB|Executes Scripts|Calls Main|Duration (s)|Category|Timeout"
        echo "--------|-----|------|-------|----------------|----------|------------|--------|--------"
        
        for test_file in "${test_files[@]}"; do
            analyze_test_file "${test_file}"
        done
    } | column -t -s '|' > "${ANALYSIS_FILE}"
    
    # Summary
    echo
    print_message "${GREEN}" "Analysis complete!"
    print_message "${BLUE}" "Results saved to: ${ANALYSIS_FILE}"
    echo
    
    # Show summary
    local fast_count
    fast_count=$(grep -c "fast" "${ANALYSIS_FILE}" 2>/dev/null || echo "0")
    local medium_count
    medium_count=$(grep -c "medium" "${ANALYSIS_FILE}" 2>/dev/null || echo "0")
    local slow_count
    slow_count=$(grep -c "slow" "${ANALYSIS_FILE}" 2>/dev/null || echo "0")
    local very_slow_count
    very_slow_count=$(grep -c "very_slow" "${ANALYSIS_FILE}" 2>/dev/null || echo "0")
    
    print_message "${GREEN}" "Summary:"
    echo "  Fast (<${FAST_THRESHOLD}s): ${fast_count}"
    echo "  Medium (${FAST_THRESHOLD}-${MEDIUM_THRESHOLD}s): ${medium_count}"
    echo "  Slow (${MEDIUM_THRESHOLD}-${SLOW_THRESHOLD}s): ${slow_count}"
    echo "  Very Slow (>${SLOW_THRESHOLD}s): ${very_slow_count}"
    echo
    
    # Show slowest tests
    print_message "${YELLOW}" "Slowest tests:"
    tail -n +3 "${ANALYSIS_FILE}" | sort -k7 -rn | head -5 | while IFS= read -r line; do
        echo "  ${line}"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
