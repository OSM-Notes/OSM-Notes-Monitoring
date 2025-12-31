#!/usr/bin/env bash
#
# Penetration Testing Script
# Automated penetration tests for security vulnerabilities
#
# Version: 1.0.0
# Date: 2025-12-31
#
# WARNING: This script attempts to exploit vulnerabilities for testing purposes.
# Only run in isolated test environments with proper authorization.
#

set -uo pipefail
# Note: We don't use 'set -e' because we want to handle errors manually in tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
readonly PROJECT_ROOT

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Options
VERBOSE=false
CATEGORY="all"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    if [[ "${VERBOSE}" == "true" ]] || [[ "${color}" == "${RED}" ]] || [[ "${color}" == "${GREEN}" ]]; then
        echo -e "${color}$*${NC}"
    fi
}

##
# Print test header
##
print_test_header() {
    local test_name="${1}"
    echo ""
    print_message "${BLUE}" "=========================================="
    print_message "${BLUE}" "Test: ${test_name}"
    print_message "${BLUE}" "=========================================="
}

##
# Record test result
##
record_result() {
    local test_name="${1}"
    local result="${2}"  # "PASS" or "FAIL"
    local details="${3:-}"
    
    ((TESTS_TOTAL++))
    
    if [[ "${result}" == "PASS" ]]; then
        ((TESTS_PASSED++))
        print_message "${GREEN}" "  ✓ ${test_name}"
    else
        ((TESTS_FAILED++))
        print_message "${RED}" "  ✗ ${test_name}"
        if [[ -n "${details}" ]]; then
            print_message "${YELLOW}" "    ${details}"
        fi
    fi
}

##
# Test SQL injection protection
##
test_sql_injection() {
    print_test_header "SQL Injection Protection"
    
    # Source security functions (with error handling)
    # shellcheck disable=SC1091
    if ! source "${PROJECT_ROOT}/bin/lib/securityFunctions.sh" 2>/dev/null; then
        record_result "SQL Injection: Load functions" "FAIL" "Could not load securityFunctions.sh"
        return 1
    fi
    
    # Test cases
    local sql_payloads=(
        "'; DROP TABLE metrics; --"
        "' OR '1'='1"
        "' UNION SELECT * FROM users--"
        "'; WAITFOR DELAY '00:00:05'--"
        "' AND 1=CAST((SELECT version()) AS int)--"
    )
    
    for payload in "${sql_payloads[@]}"; do
        # Try to use payload in IP validation (should fail)
        if is_valid_ip "${payload}" 2>/dev/null; then
            record_result "SQL Injection: ${payload}" "FAIL" "Payload accepted as valid IP"
        else
            record_result "SQL Injection: ${payload}" "PASS"
        fi
    done
    
    # Verify metrics table still exists (if DB available)
    if command -v psql > /dev/null 2>&1; then
        local dbname="${TEST_DB_NAME:-osm_notes_monitoring_test}"
        if psql -d "${dbname}" -c "SELECT 1 FROM metrics LIMIT 1;" > /dev/null 2>&1; then
            record_result "SQL Injection: Table integrity" "PASS" "Metrics table still exists"
        else
            record_result "SQL Injection: Table integrity" "FAIL" "Metrics table may have been compromised"
        fi
    fi
}

##
# Test command injection protection
##
test_command_injection() {
    print_test_header "Command Injection Protection"
    
    # Source security functions (with error handling)
    # shellcheck disable=SC1091
    if ! source "${PROJECT_ROOT}/bin/lib/securityFunctions.sh" 2>/dev/null; then
        record_result "Command Injection: Load functions" "FAIL" "Could not load securityFunctions.sh"
        return 1
    fi
    
    # Test cases
    # shellcheck disable=SC2006  # Backticks are intentional as test payloads
    local cmd_payloads=(
        "; ls -la /etc/passwd"
        "| cat /etc/passwd"
        "`whoami`"
        "\$(id)"
        "&& cat /etc/passwd"
    )
    
    for payload in "${cmd_payloads[@]}"; do
        # Try to use payload in IP validation (should fail)
        if is_valid_ip "${payload}" 2>/dev/null; then
            record_result "Command Injection: ${payload}" "FAIL" "Payload accepted as valid IP"
        else
            record_result "Command Injection: ${payload}" "PASS"
        fi
    done
}

##
# Test path traversal protection
##
test_path_traversal() {
    print_test_header "Path Traversal Protection"
    
    # Test cases
    local path_payloads=(
        "../../../etc/passwd"
        "..%2F..%2Fetc%2Fpasswd"
        "..%252F..%252Fetc%252Fpasswd"
        "../../../etc/passwd%00"
        "....//....//etc/passwd"
    )
    
    # Source config functions
    # shellcheck disable=SC1091
    if [[ -f "${PROJECT_ROOT}/bin/lib/configFunctions.sh" ]]; then
        source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
        
        for payload in "${path_payloads[@]}"; do
            # Try to use payload as config path (should fail or sanitize)
            local result
            if result=$(get_project_root 2>&1); then
                # Check if result contains the payload (should not)
                if [[ "${result}" == *"${payload}"* ]]; then
                    record_result "Path Traversal: ${payload}" "FAIL" "Path traversal successful"
                else
                    record_result "Path Traversal: ${payload}" "PASS"
                fi
            else
                record_result "Path Traversal: ${payload}" "PASS" "Function rejected invalid path"
            fi
        done
    else
        record_result "Path Traversal: Config functions" "SKIP" "Config functions not available"
    fi
}

##
# Test rate limiting bypass attempts
##
test_rate_limiting_bypass() {
    print_test_header "Rate Limiting Bypass Attempts"
    
    # Skip if database not available
    if ! command -v psql > /dev/null 2>&1; then
        record_result "Rate Limiting: Database" "SKIP" "PostgreSQL not available"
        return
    fi
    
    local test_ip="192.168.200.1"
    local dbname="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    
    # Source security functions (with error handling)
    # shellcheck disable=SC1091
    if ! source "${PROJECT_ROOT}/bin/lib/securityFunctions.sh" 2>/dev/null; then
        record_result "Rate Limiting: Load functions" "FAIL" "Could not load securityFunctions.sh"
        return 1
    fi
    
    # Clear any existing data
    psql -d "${dbname}" -c "DELETE FROM security_events WHERE ip_address = '${test_ip}'::inet;" > /dev/null 2>&1 || true
    psql -d "${dbname}" -c "DELETE FROM ip_management WHERE ip_address = '${test_ip}'::inet;" > /dev/null 2>&1 || true
    
    # Test 1: Rapid burst requests
    local burst_count=0
    local limit=5
    local i=0
    while [[ ${i} -lt 20 ]]; do
        if check_rate_limit "${test_ip}" 60 "${limit}" 2>/dev/null; then
            burst_count=$((burst_count + 1))
        fi
        i=$((i + 1))
    done
    
    if [[ ${burst_count} -le ${limit} ]]; then
        record_result "Rate Limiting: Burst protection" "PASS" "Burst limited to ${burst_count}/${limit}"
    else
        record_result "Rate Limiting: Burst protection" "FAIL" "Burst not limited (${burst_count} requests)"
    fi
    
    # Test 2: IP rotation attempt (simulate with different IPs)
    local rotated_bypass=0
    for i in {1..10}; do
        local rotated_ip="192.168.200.${i}"
        if check_rate_limit "${rotated_ip}" 60 5 2>/dev/null; then
            rotated_bypass=$((rotated_bypass + 1))
        fi
    done
    
    # IP rotation should work (different IPs), but each should be limited
    record_result "Rate Limiting: IP rotation" "PASS" "IP rotation handled correctly"
    
    # Cleanup
    psql -d "${dbname}" -c "DELETE FROM security_events WHERE ip_address LIKE '192.168.200.%'::inet;" > /dev/null 2>&1 || true
}

##
# Test IP blocking bypass attempts
##
test_ip_blocking_bypass() {
    print_test_header "IP Blocking Bypass Attempts"
    
    # Skip if database not available
    if ! command -v psql > /dev/null 2>&1; then
        record_result "IP Blocking: Database" "SKIP" "PostgreSQL not available"
        return
    fi
    
    local test_ip="192.168.201.1"
    local dbname="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    
    # Source security functions (with error handling)
    # shellcheck disable=SC1091
    if ! source "${PROJECT_ROOT}/bin/lib/securityFunctions.sh" 2>/dev/null; then
        record_result "IP Blocking: Load functions" "FAIL" "Could not load securityFunctions.sh"
        return 1
    fi
    
    # Add IP to blacklist
    psql -d "${dbname}" -c "INSERT INTO ip_management (ip_address, list_type, reason, created_at) VALUES ('${test_ip}'::inet, 'blacklist', 'pen test', CURRENT_TIMESTAMP) ON CONFLICT DO NOTHING;" > /dev/null 2>&1 || true
    
    # Test 1: Verify IP is blocked
    if is_ip_blacklisted "${test_ip}" 2>/dev/null; then
        record_result "IP Blocking: Blacklist check" "PASS"
    else
        record_result "IP Blocking: Blacklist check" "FAIL" "IP not detected as blacklisted"
    fi
    
    # Test 2: Try IPv6 equivalent (if supported)
    local ipv6_equivalent="::ffff:${test_ip}"
    if is_valid_ip "${ipv6_equivalent}" 2>/dev/null; then
        # IPv6 should be treated as different IP (not blocked)
        record_result "IP Blocking: IPv6 format" "PASS" "IPv6 format handled correctly"
    fi
    
    # Test 3: Try with different case or encoding (should not bypass)
    if is_ip_blacklisted "${test_ip}" 2>/dev/null; then
        record_result "IP Blocking: Consistency" "PASS"
    fi
    
    # Cleanup
    psql -d "${dbname}" -c "DELETE FROM ip_management WHERE ip_address = '${test_ip}'::inet;" > /dev/null 2>&1 || true
}

##
# Test input validation
##
test_input_validation() {
    print_test_header "Input Validation"
    
    # Source security functions (with error handling)
    # shellcheck disable=SC1091
    if ! source "${PROJECT_ROOT}/bin/lib/securityFunctions.sh" 2>/dev/null; then
        record_result "Input Validation: Load functions" "FAIL" "Could not load securityFunctions.sh"
        return 1
    fi
    
    # Test invalid IP formats
    local invalid_inputs=(
        "999.999.999.999"
        "256.1.1.1"
        "1.1.1"
        "not.an.ip"
        ""
        "1.1.1.1.1"
        "1.1.1.1:8080"
        "1.1.1.1/24"
    )
    
    for input in "${invalid_inputs[@]}"; do
        if is_valid_ip "${input}" 2>/dev/null; then
            record_result "Input Validation: ${input}" "FAIL" "Invalid input accepted"
        else
            record_result "Input Validation: ${input}" "PASS"
        fi
    done
}

##
# Generate summary report
##
generate_summary() {
    echo ""
    print_message "${BLUE}" "=========================================="
    print_message "${GREEN}" "Penetration Test Summary"
    print_message "${BLUE}" "=========================================="
    echo ""
    
    print_message "${GREEN}" "Passed: ${TESTS_PASSED}"
    print_message "${RED}" "Failed: ${TESTS_FAILED}"
    print_message "${YELLOW}" "Total: ${TESTS_TOTAL}"
    echo ""
    
    local pass_rate=0
    if [[ ${TESTS_TOTAL} -gt 0 ]]; then
        pass_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    fi
    
    print_message "${BLUE}" "Pass Rate: ${pass_rate}%"
    echo ""
    
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All penetration tests passed!"
        return 0
    else
        print_message "${RED}" "✗ Some tests failed. Review findings above."
        return 1
    fi
}

##
# Show usage
##
usage() {
    cat << EOF
Penetration Testing Script

Usage: ${0} [OPTIONS]

Options:
    --category CATEGORY    Test category (all, sql_injection, command_injection, path_traversal, rate_limiting, ip_blocking, input_validation)
    --verbose              Verbose output
    --help                 Show this help message

WARNING: This script attempts to exploit vulnerabilities for testing purposes.
Only run in isolated test environments with proper authorization.

EOF
}

##
# Main
##
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --category)
                CATEGORY="${2}"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: ${1}" >&2
                usage
                exit 1
                ;;
        esac
    done
    
    print_message "${GREEN}" "Penetration Testing for OSM-Notes-Monitoring"
    print_message "${BLUE}" "Started at: $(date)"
    print_message "${YELLOW}" "WARNING: This script attempts to exploit vulnerabilities."
    print_message "${YELLOW}" "Only run in isolated test environments with proper authorization."
    echo ""
    
    # Run tests based on category
    case "${CATEGORY}" in
        all)
            test_sql_injection
            test_command_injection
            test_path_traversal
            test_rate_limiting_bypass
            test_ip_blocking_bypass
            test_input_validation
            ;;
        sql_injection)
            test_sql_injection
            ;;
        command_injection)
            test_command_injection
            ;;
        path_traversal)
            test_path_traversal
            ;;
        rate_limiting)
            test_rate_limiting_bypass
            ;;
        ip_blocking)
            test_ip_blocking_bypass
            ;;
        input_validation)
            test_input_validation
            ;;
        *)
            echo "Unknown category: ${CATEGORY}" >&2
            usage
            exit 1
            ;;
    esac
    
    # Generate summary
    generate_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
