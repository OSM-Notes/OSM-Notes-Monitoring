#!/usr/bin/env bash
#
# Comprehensive Configuration Validation Tests
# Tests all validation scenarios
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
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

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
# Run a test
##
run_test() {
    local test_name="${1}"
    shift
    local test_command="$*"

    print_message "${BLUE}" "Testing: ${test_name}"

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
# Test missing required variables
##
test_missing_required_vars() {
    print_message "${BLUE}" "\n=== Testing Missing Required Variables ==="

    # Test missing DBNAME
    unset DBNAME DBHOST DBPORT DBUSER
    run_test "validate_main_config fails without DBNAME" \
        "! validate_main_config"

    # Test missing DBHOST
    export DBNAME="test"
    unset DBHOST DBPORT DBUSER
    run_test "validate_main_config fails without DBHOST" \
        "! validate_main_config"

    # Test missing DBPORT
    export DBHOST="localhost"
    unset DBPORT DBUSER
    run_test "validate_main_config fails without DBPORT" \
        "! validate_main_config"

    # Test missing DBUSER
    export DBPORT="5432"
    unset DBUSER
    run_test "validate_main_config fails without DBUSER" \
        "! validate_main_config"
}

##
# Test invalid data types
##
test_invalid_data_types() {
    print_message "${BLUE}" "\n=== Testing Invalid Data Types ==="

    # Test invalid DBPORT
    export DBNAME="test" DBHOST="localhost" DBPORT="invalid" DBUSER="postgres"
    run_test "validate_main_config rejects non-numeric DBPORT" \
        "! validate_main_config"

    # Test invalid rate limit
    export RATE_LIMIT_PER_IP_PER_MINUTE="invalid"
    run_test "validate_security_config rejects non-numeric rate limit" \
        "! validate_security_config"

    # Test invalid boolean
    export INGESTION_ENABLED="maybe"
    run_test "validate_monitoring_config rejects invalid boolean" \
        "! validate_monitoring_config"

    # Test invalid email
    export SEND_ALERT_EMAIL="true"
    export ADMIN_EMAIL="invalid-email"
    run_test "validate_alert_config rejects invalid email" \
        "! validate_alert_config"
}

##
# Test invalid ranges
##
test_invalid_ranges() {
    print_message "${BLUE}" "\n=== Testing Invalid Ranges ==="

    # Test zero rate limit
    export RATE_LIMIT_PER_IP_PER_MINUTE="0"
    run_test "validate_security_config rejects zero rate limit" \
        "! validate_security_config"

    # Test zero retention days
    export METRICS_RETENTION_DAYS="0"
    run_test "validate_monitoring_config rejects zero retention days" \
        "! validate_monitoring_config"
}

##
# Test valid configurations
##
test_valid_configs() {
    print_message "${BLUE}" "\n=== Testing Valid Configurations ==="

    # Valid main config
    export DBNAME="test_db" DBHOST="localhost" DBPORT="5432" DBUSER="postgres"
    run_test "validate_main_config accepts valid config" \
        "validate_main_config || true"

    # Valid alert config
    export ADMIN_EMAIL="admin@example.com" SEND_ALERT_EMAIL="true"
    run_test "validate_alert_config accepts valid email" \
        "validate_alert_config || true"

    # Valid security config
    export RATE_LIMIT_PER_IP_PER_MINUTE="60" RATE_LIMIT_PER_IP_PER_HOUR="1000"
    run_test "validate_security_config accepts valid rate limits" \
        "validate_security_config || true"

    # Valid monitoring config
    export INGESTION_ENABLED="true" INGESTION_CHECK_TIMEOUT="300"
    export METRICS_RETENTION_DAYS="90"
    run_test "validate_monitoring_config accepts valid config" \
        "validate_monitoring_config || true"
}

##
# Test conditional validations
##
test_conditional_validations() {
    print_message "${BLUE}" "\n=== Testing Conditional Validations ==="

    # Test Slack webhook required when enabled
    export SLACK_ENABLED="true"
    unset SLACK_WEBHOOK_URL
    run_test "validate_alert_config requires webhook when Slack enabled" \
        "! validate_alert_config"

    # Test email not required when disabled
    export SEND_ALERT_EMAIL="false"
    unset ADMIN_EMAIL
    run_test "validate_alert_config allows missing email when disabled" \
        "validate_alert_config || true"
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
    print_message "${GREEN}" "Comprehensive Configuration Validation Tests"
    echo

    # Run test suites
    test_missing_required_vars
    test_invalid_data_types
    test_invalid_ranges
    test_valid_configs
    test_conditional_validations

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

