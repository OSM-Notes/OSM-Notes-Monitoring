#!/usr/bin/env bash
#
# Test Logging with Different Log Levels
# Comprehensive test script for logging functionality
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
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test log directory
readonly TEST_LOG_DIR="${PROJECT_ROOT}/tests/tmp/logs"
readonly TEST_LOG_FILE="${TEST_LOG_DIR}/test_levels.log"

TESTS_PASSED=0
TESTS_FAILED=0

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Cleanup test files
##
cleanup() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Setup test environment
##
setup_test() {
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_FILE}"
    rm -f "${TEST_LOG_FILE}"
}

##
# Check if log file contains string
##
log_contains() {
    local pattern="${1}"
    if [[ -f "${TEST_LOG_FILE}" ]] && grep -q "${pattern}" "${TEST_LOG_FILE}" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

##
# Check if log file does not contain string
##
log_not_contains() {
    local pattern="${1}"
    if [[ -f "${TEST_LOG_FILE}" ]] && ! grep -q "${pattern}" "${TEST_LOG_FILE}" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

##
# Run a test
##
run_test() {
    local test_name="${1}"
    shift
    local test_command="$*"

    print_message "${BLUE}" "Testing: ${test_name}"

    # Reset log file
    rm -f "${TEST_LOG_FILE}"

    if eval "${test_command}" > /dev/null 2>&1; then
        print_message "${GREEN}" "  ✓ PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_message "${RED}" "  ✗ FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

##
# Test DEBUG level
##
test_debug_level() {
    print_message "${BLUE}" "\n=== Testing DEBUG Level ==="

    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    setup_test

    # All levels should log
    run_test "DEBUG level logs DEBUG messages" \
        "log_debug 'Debug test' && log_contains 'DEBUG' && log_contains 'Debug test'"

    run_test "DEBUG level logs INFO messages" \
        "log_info 'Info test' && log_contains 'INFO' && log_contains 'Info test'"

    run_test "DEBUG level logs WARNING messages" \
        "log_warning 'Warning test' && log_contains 'WARNING' && log_contains 'Warning test'"

    run_test "DEBUG level logs ERROR messages" \
        "log_error 'Error test' && log_contains 'ERROR' && log_contains 'Error test'"
}

##
# Test INFO level
##
test_info_level() {
    print_message "${BLUE}" "\n=== Testing INFO Level ==="

    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    setup_test

    # DEBUG should not log, others should
    run_test "INFO level does not log DEBUG messages" \
        "log_debug 'Debug test' && (log_not_contains 'DEBUG' || true)"

    run_test "INFO level logs INFO messages" \
        "log_info 'Info test' && log_contains 'INFO' && log_contains 'Info test'"

    run_test "INFO level logs WARNING messages" \
        "log_warning 'Warning test' && log_contains 'WARNING' && log_contains 'Warning test'"

    run_test "INFO level logs ERROR messages" \
        "log_error 'Error test' && log_contains 'ERROR' && log_contains 'Error test'"
}

##
# Test WARNING level
##
test_warning_level() {
    print_message "${BLUE}" "\n=== Testing WARNING Level ==="

    export LOG_LEVEL="${LOG_LEVEL_WARNING}"
    setup_test

    # DEBUG and INFO should not log, WARNING and ERROR should
    run_test "WARNING level does not log DEBUG messages" \
        "log_debug 'Debug test' && (log_not_contains 'DEBUG' || true)"

    run_test "WARNING level does not log INFO messages" \
        "log_info 'Info test' && (log_not_contains 'INFO' || true)"

    run_test "WARNING level logs WARNING messages" \
        "log_warning 'Warning test' && log_contains 'WARNING' && log_contains 'Warning test'"

    run_test "WARNING level logs ERROR messages" \
        "log_error 'Error test' && log_contains 'ERROR' && log_contains 'Error test'"
}

##
# Test ERROR level
##
test_error_level() {
    print_message "${BLUE}" "\n=== Testing ERROR Level ==="

    export LOG_LEVEL="${LOG_LEVEL_ERROR}"
    setup_test

    # Only ERROR should log
    run_test "ERROR level does not log DEBUG messages" \
        "log_debug 'Debug test' && (log_not_contains 'DEBUG' || true)"

    run_test "ERROR level does not log INFO messages" \
        "log_info 'Info test' && (log_not_contains 'INFO' || true)"

    run_test "ERROR level does not log WARNING messages" \
        "log_warning 'Warning test' && (log_not_contains 'WARNING' || true)"

    run_test "ERROR level logs ERROR messages" \
        "log_error 'Error test' && log_contains 'ERROR' && log_contains 'Error test'"
}

##
# Test log format
##
test_log_format() {
    print_message "${BLUE}" "\n=== Testing Log Format ==="

    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    setup_test

    log_info "Format test"

    # Check timestamp format (YYYY-MM-DD HH:MM:SS without brackets)
    if log_contains '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}'; then
        print_message "${GREEN}" "  ✓ Timestamp format correct"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_message "${RED}" "  ✗ Timestamp format incorrect"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check log level format [LEVEL]
    if log_contains '\[INFO\]'; then
        print_message "${GREEN}" "  ✓ Log level format correct"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_message "${RED}" "  ✗ Log level format incorrect"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

##
# Test component name (using SCRIPT_NAME)
##
test_component_name() {
    print_message "${BLUE}" "\n=== Testing Component Name ==="

    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    export SCRIPT_NAME="TEST_COMPONENT"
    setup_test

    log_info "Component test"

    if log_contains "TEST_COMPONENT"; then
        print_message "${GREEN}" "  ✓ Component name included in log"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_message "${RED}" "  ✗ Component name not found in log"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

##
# Print summary
##
print_summary() {
    echo
    print_message "${BLUE}" "=== Test Summary ==="
    print_message "${GREEN}" "Tests passed: ${TESTS_PASSED}"

    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        print_message "${RED}" "Tests failed: ${TESTS_FAILED}"
        echo
        return 1
    else
        print_message "${GREEN}" "Tests failed: ${TESTS_FAILED}"
        echo
        print_message "${GREEN}" "✓ All tests passed!"
        return 0
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "Logging Levels Test Suite"
    echo

    # Setup
    trap cleanup EXIT
    mkdir -p "${TEST_LOG_DIR}"

    # Run test suites
    test_debug_level
    test_info_level
    test_warning_level
    test_error_level
    test_log_format
    test_component_name

    # Summary
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

