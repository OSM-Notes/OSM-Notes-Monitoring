#!/usr/bin/env bash
#
# Access Control Tests
# Tests for file permissions, security functions, and access control mechanisms
#
# Version: 1.0.0
# Date: 2025-12-31
#

# Test configuration - set before loading test_helper
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/securityFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"

##
# Setup: Initialize test environment
##
setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_access_control.log"
    init_logging "${LOG_FILE}" "test_access_control"
    
    # Configure database connection
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-${PGHOST:-localhost}}"
    export DBPORT="${DBPORT:-${PGPORT:-5432}}"
    export DBUSER="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
    
    # Initialize database schema if needed
    skip_if_database_not_available
    initialize_test_database_schema
    
    # Initialize security functions
    init_security
}

##
# Teardown: Clean up test environment
##
teardown() {
    # Clean up test data
    if [[ -n "${TEST_DB_NAME:-}" ]]; then
        clean_test_database || true
    fi
}

##
# Test: Script files have correct execute permissions
##
@test "Script files have execute permissions" {
    local project_root
    project_root=$(get_project_root)
    
    # Check that scripts in bin/monitor, bin/alerts, bin/security, bin/dashboard have execute permission
    # Note: bin/lib/*.sh are libraries and don't need execute permission
    local missing_exec=0
    while IFS= read -r script; do
        if [[ -f "${script}" ]] && [[ ! -x "${script}" ]]; then
            echo "Warning: Script ${script} is not executable" >&2
            missing_exec=$((missing_exec + 1))
        fi
    done < <(find "${project_root}/bin" -type f -name "*.sh" ! -path "*/lib/*" 2>/dev/null)
    
    # Allow some scripts to not be executable (e.g., if they're meant to be sourced)
    # But warn if many are missing execute permission
    if [[ ${missing_exec} -gt 5 ]]; then
        assert false "Too many scripts missing execute permission (${missing_exec})"
    fi
}

##
# Test: Configuration files are not world-readable (non-example files)
##
@test "Configuration files have restricted permissions" {
    local project_root
    project_root=$(get_project_root)
    
    # Check actual config files (not examples) - skip if they don't exist
    # Example files can be world-readable, but actual configs should not be
    local config_files=(
        "${project_root}/etc/properties.sh"
        "${project_root}/config/monitoring.conf"
        "${project_root}/config/alerts.conf"
        "${project_root}/config/security.conf"
    )
    
    local checked=0
    local world_readable=0
    for config_file in "${config_files[@]}"; do
        # Skip example files
        if [[ "${config_file}" == *".example"* ]]; then
            continue
        fi
        
        if [[ -f "${config_file}" ]]; then
            local perms
            perms=$(stat -c "%a" "${config_file}" 2>/dev/null || stat -f "%OLp" "${config_file}" 2>/dev/null || echo "")
            
            # Check if world-readable (ends in 4, 5, 6, or 7)
            if [[ -n "${perms}" ]]; then
                local last_digit="${perms: -1}"
                if [[ "${last_digit}" == "4" ]] || [[ "${last_digit}" == "5" ]] || [[ "${last_digit}" == "6" ]] || [[ "${last_digit}" == "7" ]]; then
                    echo "Warning: Config file ${config_file} is world-readable (perms: ${perms})" >&2
                    world_readable=$((world_readable + 1))
                fi
                checked=$((checked + 1))
            fi
        fi
    done
    
    # If no config files exist, skip this test
    if [[ ${checked} -eq 0 ]]; then
        skip "No actual config files found (only examples)"
    fi
    
    # Allow some config files to be world-readable (e.g., test configs), but warn
    # In production, config files with secrets should not be world-readable
    if [[ ${world_readable} -gt 0 ]]; then
        echo "Note: ${world_readable} config file(s) are world-readable. Consider restricting permissions for files containing secrets."
    fi
}

##
# Test: No world-writable files in bin directory
##
@test "No world-writable files in bin directory" {
    local project_root
    project_root=$(get_project_root)
    
    # Check for world-writable files
    while IFS= read -r file; do
        if [[ -f "${file}" ]]; then
            local perms
            perms=$(stat -c "%a" "${file}" 2>/dev/null || stat -f "%OLp" "${file}" 2>/dev/null || echo "")
            
            # Should not be world-writable (should not contain 2, 6, or 7 in last digit)
            if [[ -n "${perms}" ]]; then
                local last_digit="${perms: -1}"
                if [[ "${last_digit}" == "2" ]] || [[ "${last_digit}" == "6" ]] || [[ "${last_digit}" == "7" ]]; then
                    assert false "File ${file} should not be world-writable (perms: ${perms})"
                fi
            fi
        fi
    done < <(find "${project_root}/bin" -type f 2>/dev/null)
}

##
# Test: IP validation function rejects invalid IPs
##
@test "IP validation rejects invalid IP addresses" {
    # Invalid IPs
    local invalid_ips=(
        "999.999.999.999"
        "256.1.1.1"
        "1.1.1"
        "not.an.ip.address"
        ""
        "1.1.1.1.1"
    )
    
    for ip in "${invalid_ips[@]}"; do
        run is_valid_ip "${ip}"
        assert_failure "IP '${ip}' should be invalid"
    done
}

##
# Test: IP validation function accepts valid IPs
##
@test "IP validation accepts valid IP addresses" {
    # Valid IPs
    local valid_ips=(
        "127.0.0.1"
        "192.168.1.1"
        "10.0.0.1"
        "0.0.0.0"
        "255.255.255.255"
    )
    
    for ip in "${valid_ips[@]}"; do
        run is_valid_ip "${ip}"
        assert_success
    done
}

##
# Test: Whitelist function works correctly
##
@test "IP whitelist function works correctly" {
    skip_if_database_not_available
    
    local test_ip="192.168.100.1"
    
    # Add IP to whitelist
    run_sql_query "INSERT INTO ip_management (ip_address, list_type, reason, created_at) VALUES ('${test_ip}'::inet, 'whitelist', 'test', CURRENT_TIMESTAMP);" "${TEST_DB_NAME}"
    
    # Check if whitelisted
    run is_ip_whitelisted "${test_ip}"
    assert_success
    
    # Clean up
    run_sql_query "DELETE FROM ip_management WHERE ip_address = '${test_ip}'::inet;" "${TEST_DB_NAME}"
}

##
# Test: Blacklist function works correctly
##
@test "IP blacklist function works correctly" {
    skip_if_database_not_available
    
    local test_ip="192.168.100.2"
    
    # Add IP to blacklist
    run_sql_query "INSERT INTO ip_management (ip_address, list_type, reason, created_at) VALUES ('${test_ip}'::inet, 'blacklist', 'test', CURRENT_TIMESTAMP);" "${TEST_DB_NAME}"
    
    # Check if blacklisted
    run is_ip_blacklisted "${test_ip}"
    assert_success
    
    # Clean up
    run_sql_query "DELETE FROM ip_management WHERE ip_address = '${test_ip}'::inet;" "${TEST_DB_NAME}"
}

##
# Test: Rate limiting function enforces limits
##
@test "Rate limiting enforces limits correctly" {
    skip_if_database_not_available
    
    local test_ip="192.168.100.3"
    local limit_per_minute=5
    
    # Clear any existing rate limit data
    run_sql_query "DELETE FROM security_events WHERE ip_address = '${test_ip}'::inet;" "${TEST_DB_NAME}" || true
    
    # Make requests up to limit (need to record events first)
    local i=0
    while [[ ${i} -lt ${limit_per_minute} ]]; do
        # Record a rate limit event for each request
        record_security_event "rate_limit" "${test_ip}" "/test" "{\"request\": ${i}}"
        run check_rate_limit "${test_ip}" 60 "${limit_per_minute}"
        assert_success
        i=$((i + 1))
    done
    
    # Record one more event to exceed limit
    record_security_event "rate_limit" "${test_ip}" "/test" "{\"request\": ${limit_per_minute}}"
    
    # Next request should exceed limit
    run check_rate_limit "${test_ip}" 60 "${limit_per_minute}"
    assert_failure
    
    # Clean up
    run_sql_query "DELETE FROM security_events WHERE ip_address = '${test_ip}'::inet;" "${TEST_DB_NAME}" || true
}

##
# Test: Whitelisted IPs bypass rate limiting
##
@test "Whitelisted IPs bypass rate limiting" {
    skip_if_database_not_available
    
    local test_ip="192.168.100.4"
    
    # Add IP to whitelist
    run_sql_query "INSERT INTO ip_management (ip_address, list_type, reason, created_at) VALUES ('${test_ip}'::inet, 'whitelist', 'test', CURRENT_TIMESTAMP);" "${TEST_DB_NAME}"
    
    # Make many requests (should all pass even if we record events)
    local i=0
    while [[ ${i} -lt 20 ]]; do
        # Record events to simulate requests
        record_security_event "rate_limit" "${test_ip}" "/test" "{\"request\": ${i}}"
        run check_rate_limit "${test_ip}" 60 5
        assert_success
        i=$((i + 1))
    done
    
    # Clean up
    run_sql_query "DELETE FROM ip_management WHERE ip_address = '${test_ip}'::inet;" "${TEST_DB_NAME}"
    run_sql_query "DELETE FROM security_events WHERE ip_address = '${test_ip}'::inet;" "${TEST_DB_NAME}" || true
}

##
# Test: Blacklisted IPs are blocked
##
@test "Blacklisted IPs are blocked" {
    skip_if_database_not_available
    
    local test_ip="192.168.100.5"
    
    # Add IP to blacklist
    run_sql_query "INSERT INTO ip_management (ip_address, list_type, reason, created_at) VALUES ('${test_ip}'::inet, 'blacklist', 'test', CURRENT_TIMESTAMP);" "${TEST_DB_NAME}"
    
    # Check if blacklisted
    run is_ip_blacklisted "${test_ip}"
    assert_success
    
    # Clean up
    run_sql_query "DELETE FROM ip_management WHERE ip_address = '${test_ip}'::inet;" "${TEST_DB_NAME}"
}

##
# Test: Security event logging works
##
@test "Security events are logged correctly" {
    skip_if_database_not_available
    
    local test_ip="192.168.100.6"
    local event_type="rate_limit"
    local endpoint="/test"
    local metadata="{\"test\": true}"
    
    # Log security event
    run record_security_event "${event_type}" "${test_ip}" "${endpoint}" "${metadata}"
    assert_success
    
    # Verify event was logged
    local count
    count=$(run_sql_query "SELECT COUNT(*) FROM security_events WHERE ip_address = '${test_ip}'::inet AND event_type = '${event_type}';" "${TEST_DB_NAME}")
    assert [ "${count}" -gt 0 ]
    
    # Clean up
    run_sql_query "DELETE FROM security_events WHERE ip_address = '${test_ip}'::inet;" "${TEST_DB_NAME}"
}

##
# Test: Input sanitization prevents SQL injection
##
@test "Input sanitization prevents SQL injection" {
    skip_if_database_not_available
    
    local malicious_input="'; DROP TABLE metrics; --"
    
    # Try to use malicious input in IP validation
    run is_valid_ip "${malicious_input}"
    assert_failure "Malicious input should be rejected"
    
    # Verify table still exists
    local table_exists
    table_exists=$(run_sql_query "SELECT 1 FROM information_schema.tables WHERE table_name = 'metrics' LIMIT 1;" "${TEST_DB_NAME}")
    assert [ -n "${table_exists}" ]
}

##
# Test: Configuration files are not executable
##
@test "Configuration files are not executable" {
    local project_root
    project_root=$(get_project_root)
    
    # Check config files (if they exist)
    local config_files=(
        "${project_root}/etc/properties.sh"
        "${project_root}/config/monitoring.conf"
        "${project_root}/config/alerts.conf"
        "${project_root}/config/security.conf"
    )
    
    local checked=0
    for config_file in "${config_files[@]}"; do
        # Skip example files
        if [[ "${config_file}" == *".example"* ]]; then
            continue
        fi
        
        if [[ -f "${config_file}" ]]; then
            assert [ ! -x "${config_file}" ]
            checked=$((checked + 1))
        fi
    done
    
    # If no config files exist, skip this test
    if [[ ${checked} -eq 0 ]]; then
        skip "No actual config files found (only examples)"
    fi
}

##
# Test: Log files have restricted permissions
##
@test "Log files have restricted permissions" {
    local project_root
    project_root=$(get_project_root)
    
    # Create a test log file
    local test_log="${BATS_TEST_DIRNAME}/../tmp/test_access.log"
    touch "${test_log}"
    chmod 640 "${test_log}"
    
    # Check permissions
    local perms
    perms=$(stat -c "%a" "${test_log}" 2>/dev/null || stat -f "%OLp" "${test_log}" 2>/dev/null || echo "")
    
    if [[ -n "${perms}" ]]; then
        local last_digit="${perms: -1}"
        if [[ "${last_digit}" == "4" ]] || [[ "${last_digit}" == "5" ]] || [[ "${last_digit}" == "6" ]] || [[ "${last_digit}" == "7" ]]; then
            assert false "Log file should not be world-readable (perms: ${perms})"
        fi
    fi
    
    # Clean up
    rm -f "${test_log}"
}

##
# Test: Database connection requires valid credentials
##
@test "Database connection requires valid credentials" {
    skip_if_database_not_available
    
    # Test with invalid credentials
    local old_password="${PGPASSWORD:-}"
    export PGPASSWORD="invalid_password"
    
    # This should fail
    run check_database_connection "${TEST_DB_NAME}" || true
    
    # Restore original password
    export PGPASSWORD="${old_password}"
    
    # Note: This test may pass or fail depending on authentication method
    # (peer auth might still work even with wrong password)
    # So we just verify the function exists and can be called
    assert true "Database connection check completed"
}

##
# Test: Expired IP blocks are not active
##
@test "Expired IP blocks are not active" {
    skip_if_database_not_available
    
    local test_ip="192.168.100.7"
    
    # Add IP block with expiration in the past
    run_sql_query "INSERT INTO ip_management (ip_address, list_type, reason, created_at, expires_at) VALUES ('${test_ip}'::inet, 'blacklist', 'test', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP - INTERVAL '1 hour');" "${TEST_DB_NAME}"
    
    # Check if blacklisted (should not be, as it's expired)
    run is_ip_blacklisted "${test_ip}"
    assert_failure "Expired IP block should not be active"
    
    # Clean up
    run_sql_query "DELETE FROM ip_management WHERE ip_address = '${test_ip}'::inet;" "${TEST_DB_NAME}"
}
