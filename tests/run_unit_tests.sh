#!/usr/bin/env bash
#
# Run Unit Tests
# Executes all unit tests using BATS
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TEST_DIR=""
TEST_DIR="${SCRIPT_DIR}/unit"
readonly TEST_DIR

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
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
# Check if BATS is installed
##
check_bats() {
    if ! command -v bats > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: BATS not found. Please install BATS:"
        echo "  git clone https://github.com/bats-core/bats-core.git"
        echo "  cd bats-core"
        echo "  ./install.sh /usr/local"
        exit 1
    fi
}

##
# Run unit tests
##
run_tests() {
    local test_files
    local failed_tests=0
    
    print_message "${YELLOW}" "Running unit tests..."
    echo
    
    # Find all test files
    if [[ ! -d "${TEST_DIR}" ]]; then
        print_message "${YELLOW}" "Unit test directory not found: ${TEST_DIR}"
        print_message "${YELLOW}" "Creating directory structure..."
        mkdir -p "${TEST_DIR}"
        return 0
    fi
    
    test_files=$(find "${TEST_DIR}" -name "test_*.sh" -type f)
    
    if [[ -z "${test_files}" ]]; then
        print_message "${YELLOW}" "No unit tests found in ${TEST_DIR}"
        return 0
    fi
    
    # Run tests
    local start_time
    start_time=$(date +%s)
    
    while IFS= read -r test_file; do
        local test_start
        test_start=$(date +%s.%N 2>/dev/null || date +%s)
        print_message "${GREEN}" "Running: $(basename "${test_file}")"
        
        # Capture exit code explicitly to avoid set -e terminating the script
        local bats_exit_code=0
        bats "${test_file}" || bats_exit_code=$?
        
        local test_end
        test_end=$(date +%s.%N 2>/dev/null || date +%s)
        local test_duration
        if command -v bc >/dev/null 2>&1; then
            test_duration=$(echo "${test_end} - ${test_start}" | bc 2>/dev/null || echo "0")
            test_duration=$(printf "%.2f" "${test_duration}" 2>/dev/null || echo "0")
        else
            test_duration=$((test_end - test_start))
        fi
        
        if [[ ${bats_exit_code} -ne 0 ]]; then
            failed_tests=$((failed_tests + 1))
            print_message "${RED}" "  ✗ Failed (${test_duration}s)"
        else
            print_message "${GREEN}" "  ✓ Passed (${test_duration}s)"
        fi
        
        echo
    done <<< "${test_files}"
    
    local end_time
    end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    # Summary
    echo
    local total_tests
    total_tests=$(echo "${test_files}" | wc -l)
    local passed_tests=$((total_tests - failed_tests))
    
    print_message "${BLUE}" "Summary:"
    echo "  Total: ${total_tests}"
    echo "  Passed: ${passed_tests}"
    echo "  Failed: ${failed_tests}"
    echo "  Duration: ${total_duration}s"
    echo
    
    if [[ ${failed_tests} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All unit tests passed"
        return 0
    else
        print_message "${RED}" "✗ ${failed_tests} test suite(s) failed"
        return 1
    fi
}

##
# Main
##
main() {
    check_bats
    run_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

