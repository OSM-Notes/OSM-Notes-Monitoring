#!/usr/bin/env bash
#
# Unit Tests: rateLimiter.sh
# Tests rate limiting functionality
#
# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Not following source files is expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Set test configuration
    export RATE_LIMIT_PER_IP_PER_MINUTE="60"
    export RATE_LIMIT_PER_IP_PER_HOUR="1000"
    export RATE_LIMIT_PER_IP_PER_DAY="10000"
    export RATE_LIMIT_BURST_SIZE="10"
    export RATE_LIMIT_PER_API_KEY_PER_MINUTE="100"
    export RATE_LIMIT_PER_ENDPOINT_PER_MINUTE="200"
    export RATE_LIMIT_WINDOW_SECONDS="60"
    
    # Mock database functions to avoid real DB calls
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock functions BEFORE sourcing to avoid errors
    # shellcheck disable=SC2317
    load_config() { return 0; }
    export -f load_config
    # shellcheck disable=SC2317
    init_alerting() { return 0; }
    export -f init_alerting
    # shellcheck disable=SC2317
    psql() { return 0; }
    export -f psql
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/securityFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test.log" "test_rateLimiter"
    
    # Initialize security functions
    init_security
    
    # Source rateLimiter.sh functions
    source "${BATS_TEST_DIRNAME}/../../../bin/security/rateLimiter.sh" 2>/dev/null || true
    
    # Export all functions from rateLimiter.sh if they exist
    for func in main reset_rate_limit record_request check_rate_limit_sliding_window get_rate_limit_stats; do
        if declare -f "${func}" > /dev/null 2>&1; then
            # shellcheck disable=SC2163
            export -f "${func}"
        fi
    done
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
    rm -f "${TMP_DIR}/.rate_limit_result"
}

@test "check_rate_limit_sliding_window allows request when within limit" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted to return false
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 1
    }
    export -f is_ip_blacklisted
    
    # Mock psql to return low count
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "5"
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run check
    run check_rate_limit_sliding_window "192.168.1.100" "" "" "60" "60" "10"
    
    # Should succeed (within limit)
    assert_success
}

@test "check_rate_limit_sliding_window blocks request when limit exceeded" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted to return false
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 1
    }
    export -f is_ip_blacklisted
    
    # Mock psql to return high count (over limit)
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "75"  # Over limit of 60 + burst 10 = 70
        fi
        return 0
    }
    export -f psql
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_debug() {
        return 0
    }
    export -f log_debug
    
    # shellcheck disable=SC2317
    log_warning() {
        return 0
    }
    export -f log_warning
    
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # Track if record_security_event was called
    local alert_file="${TMP_DIR}/.rate_limit_result"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        # Check if it's recording rate limit exceeded (4th arg is metadata JSON)
        local metadata="${4:-}"
        if [[ "${1}" == "rate_limit" ]] && echo "${metadata}" | grep -q "exceeded"; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run check
    run check_rate_limit_sliding_window "192.168.1.100" "" "" "60" "60" "10" || true
    
    # Should fail (rate limited)
    assert_failure
    assert_file_exists "${alert_file}"
}

@test "check_rate_limit_sliding_window allows burst requests" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted to return false
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 1
    }
    export -f is_ip_blacklisted
    
    # Mock psql to return count within burst allowance
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "65"  # Over limit (60) but within burst (60 + 10 = 70)
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run check
    run check_rate_limit_sliding_window "192.168.1.100" "" "" "60" "60" "10"
    
    # Should succeed (within burst allowance)
    assert_success
}

@test "check_rate_limit_sliding_window bypasses limit for whitelisted IP" {
    # Mock is_ip_whitelisted to return true
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 0
    }
    export -f is_ip_whitelisted
    
    # Mock psql (should not be called)
    # shellcheck disable=SC2317
    psql() {
        echo "Should not be called"
        return 1
    }
    export -f psql
    
    # Run check
    run check_rate_limit_sliding_window "192.168.1.100" "" "" "60" "60" "10"
    
    # Should succeed (whitelisted)
    assert_success
}

@test "check_rate_limit_sliding_window blocks blacklisted IP" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted to return true
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 0
    }
    export -f is_ip_blacklisted
    
    # Mock psql (should not be called)
    # shellcheck disable=SC2317
    psql() {
        echo "Should not be called"
        return 1
    }
    export -f psql
    
    # Run check
    run check_rate_limit_sliding_window "192.168.1.100" "" "" "60" "60" "10" || true
    
    # Should fail (blacklisted)
    assert_failure
}

@test "check_rate_limit_sliding_window uses per-endpoint limits" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted to return false
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 1
    }
    export -f is_ip_blacklisted
    
    # Mock psql to return count
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "150"  # Within endpoint limit of 200
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run check with endpoint
    run check_rate_limit_sliding_window "192.168.1.100" "/api/notes" "" "60" "" "10"
    
    # Should succeed (within endpoint limit)
    assert_success
}

@test "check_rate_limit_sliding_window uses per-API-key limits" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted to return false
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 1
    }
    export -f is_ip_blacklisted
    
    # Mock psql to return count
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "80"  # Within API key limit of 100
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run check with API key
    run check_rate_limit_sliding_window "192.168.1.100" "" "abc123" "60" "" "10"
    
    # Should succeed (within API key limit)
    assert_success
}

@test "record_request records security event" {
    # Track if record_security_event was called
    local event_file="${TMP_DIR}/.rate_limit_result"
    rm -f "${event_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "rate_limit" ]] && [[ "${2}" == "192.168.1.100" ]]; then
            touch "${event_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run record
    run record_request "192.168.1.100" "/api/notes" ""
    
    # Should succeed
    assert_success
    assert_file_exists "${event_file}"
}

@test "record_request includes endpoint in metadata" {
    local metadata_captured=""
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${4}" == *"endpoint"* ]] && [[ "${4}" == *"/api/notes"* ]]; then
            metadata_captured="true"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run record with endpoint
    record_request "192.168.1.100" "/api/notes" ""
    
    # Metadata should include endpoint
    assert_equal "true" "${metadata_captured}"
}

@test "record_request includes API key in metadata" {
    local metadata_captured=""
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${4}" == *"api_key"* ]] && [[ "${4}" == *"abc123"* ]]; then
            metadata_captured="true"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run record with API key
    record_request "192.168.1.100" "" "abc123"
    
    # Metadata should include API key
    assert_equal "true" "${metadata_captured}"
}

@test "get_rate_limit_stats queries database" {
    # Mock psql to return test data
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT"* ]]; then
            echo "192.168.1.100|192.168.1.100|10|2025-12-27 10:00:00|2025-12-27 10:05:00"
        fi
        return 0
    }
    export -f psql
    
    # Run stats
    run get_rate_limit_stats "192.168.1.100" ""
    
    # Should succeed
    assert_success
}

@test "reset_rate_limit deletes security events" {
    # Mock psql to track DELETE calls using file
    local delete_file="${TMP_DIR}/.delete_called"
    rm -f "${delete_file}"
    
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]] && [[ "${*}" == *"192.168.1.100"* ]]; then
            touch "${delete_file}"
        fi
        return 0
    }
    export -f psql
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # shellcheck disable=SC2317
    log_error() {
        return 0
    }
    export -f log_error
    
    # Run reset
    run reset_rate_limit "192.168.1.100" ""
    
    # Should succeed and call DELETE
    assert_success
    assert_file_exists "${delete_file}"
}

@test "reset_rate_limit handles endpoint parameter" {
    # Mock psql to track DELETE calls with endpoint using file
    local delete_file="${TMP_DIR}/.delete_called"
    rm -f "${delete_file}"
    
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]] && [[ "${*}" == *"/api/notes"* ]]; then
            touch "${delete_file}"
        fi
        return 0
    }
    export -f psql
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # shellcheck disable=SC2317
    log_error() {
        return 0
    }
    export -f log_error
    
    # Run reset with endpoint
    run reset_rate_limit "192.168.1.100" "/api/notes"
    
    # Should succeed and include endpoint in DELETE
    assert_success
    assert_file_exists "${delete_file}"
}

@test "main function check action returns ALLOWED when within limit" {
    # Mock functions
    # shellcheck disable=SC2317
    is_ip_whitelisted() { return 1; }
    # shellcheck disable=SC2317
    is_ip_blacklisted() { return 1; }
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "5"
        fi
        return 0
    }
    # shellcheck disable=SC2317
    record_security_event() { return 0; }
    
    export -f is_ip_whitelisted is_ip_blacklisted psql record_security_event
    
    # Run main with check action
    run main "check" "192.168.1.100" "" ""
    
    # Should output ALLOWED
    assert_success
    assert_output "ALLOWED"
}

@test "main function check action returns RATE_LIMITED when exceeded" {
    # Set rate limit config
    export RATE_LIMIT_WINDOW_SECONDS="60"
    export RATE_LIMIT_MAX_REQUESTS="60"
    export RATE_LIMIT_BURST_SIZE="10"
    
    # Mock functions
    # shellcheck disable=SC2317
    is_ip_whitelisted() { return 1; }
    # shellcheck disable=SC2317
    is_ip_blacklisted() { return 1; }
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "75"
        fi
        return 0
    }
    # shellcheck disable=SC2317
    record_security_event() { return 0; }
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_debug() { return 0; }
    # shellcheck disable=SC2317
    log_warning() { return 0; }
    # shellcheck disable=SC2317
    log_info() { return 0; }
    # shellcheck disable=SC2317
    log_error() { return 0; }
    
    export -f is_ip_whitelisted is_ip_blacklisted psql record_security_event log_debug log_warning log_info log_error
    
    # Mock usage function
    # shellcheck disable=SC2317
    usage() { return 0; }
    export -f usage
    
    # Run main with check action
    run main "check" "192.168.1.100" "" "" || true
    
    # Should output RATE_LIMITED
    assert_failure
    assert_output "RATE_LIMITED"
}

@test "main function record action calls record_request" {
    # Mock record_security_event to track calls using file
    local record_file="${TMP_DIR}/.record_called"
    rm -f "${record_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "rate_limit" ]] && [[ "${2}" == "192.168.1.100" ]]; then
            touch "${record_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # Run main with record action
    run main "record" "192.168.1.100" "/api/notes" ""
    
    # Should succeed and call record_security_event
    assert_success
    assert_file_exists "${record_file}"
}

@test "main function stats action calls get_rate_limit_stats" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        echo "test stats"
        return 0
    }
    export -f psql
    
    # Run main with stats action
    run main "stats" "192.168.1.100" ""
    
    # Should succeed
    assert_success
}

@test "main function reset action calls reset_rate_limit" {
    # Mock psql to track DELETE using file
    local delete_file="${TMP_DIR}/.delete_called"
    rm -f "${delete_file}"
    
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]]; then
            touch "${delete_file}"
        fi
        return 0
    }
    export -f psql
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # shellcheck disable=SC2317
    log_error() {
        return 0
    }
    export -f log_error
    
    # Run main with reset action
    run main "reset" "192.168.1.100" ""
    
    # Should succeed and call DELETE
    assert_success
    assert_file_exists "${delete_file}"
}

@test "main function shows usage for unknown action" {
    # Run main with unknown action
    run main "unknown" || true
    
    # Should fail and show usage
    assert_failure
}

@test "check_rate_limit_sliding_window handles empty count gracefully" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted to return false
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 1
    }
    export -f is_ip_blacklisted
    
    # Mock psql to return empty string
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo ""
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run check
    run check_rate_limit_sliding_window "192.168.1.100" "" "" "60" "60" "10"
    
    # Should handle gracefully (treat as 0)
    assert_success
}


@test "record_request records request successfully" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"INSERT INTO rate_limits"* ]]; then
            return 0
        fi
        return 0
    }
    export -f psql
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run record_request
    run record_request "192.168.1.100" "/api/notes" "key123"
    
    # Should succeed
    assert_success
}

@test "record_request handles database errors" {
    # Mock record_security_event to fail (simulating database error)
    # shellcheck disable=SC2317
    record_security_event() {
        return 1
    }
    export -f record_security_event
    
    # Run record_request
    run record_request "192.168.1.100" "/api/notes"
    
    # Should handle gracefully (record_request doesn't check return value)
    assert_success
}

@test "get_rate_limit_stats shows statistics for IP" {
    # Mock psql to return stats data
    # shellcheck disable=SC2317
    psql() {
        echo "192.168.1.100|60|5|2025-01-01"
        return 0
    }
    export -f psql
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # Run get_rate_limit_stats
    run get_rate_limit_stats "192.168.1.100"
    
    # Should succeed and return data (function returns raw psql output)
    assert_success
    assert_output --partial "192.168.1.100"
}

@test "get_rate_limit_stats handles database errors" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    psql() {
        return 1
    }
    export -f psql
    
    # Run get_rate_limit_stats
    run get_rate_limit_stats "192.168.1.100"
    
    # Should handle gracefully
    assert_success
}

@test "reset_rate_limit resets counters for IP" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE FROM rate_limits"* ]]; then
            return 0
        fi
        return 0
    }
    export -f psql
    
    # Run reset_rate_limit
    run reset_rate_limit "192.168.1.100"
    
    # Should succeed
    assert_success
}

@test "reset_rate_limit handles database errors" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    psql() {
        return 1
    }
    export -f psql
    
    # Mock log_error to avoid output
    # shellcheck disable=SC2317
    log_error() {
        return 0
    }
    export -f log_error
    
    # Run reset_rate_limit
    run reset_rate_limit "192.168.1.100"
    
    # Should fail when database error occurs
    assert_failure
}

@test "main function handles check action" {
    # Mock check_rate_limit_sliding_window
    # shellcheck disable=SC2317
    check_rate_limit_sliding_window() {
        return 0
    }
    export -f check_rate_limit_sliding_window
    
    # Run main with check action
    run main "check" "192.168.1.100" "/api/notes"
    
    # Should succeed
    assert_success
}

@test "main function handles record action" {
    # Mock record_request
    # shellcheck disable=SC2317
    record_request() {
        return 0
    }
    export -f record_request
    
    # Run main with record action
    run main "record" "192.168.1.100" "/api/notes"
    
    # Should succeed
    assert_success
}

@test "main function handles stats action" {
    # Mock get_rate_limit_stats
    # shellcheck disable=SC2317
    get_rate_limit_stats() {
        echo "Statistics"
        return 0
    }
    export -f get_rate_limit_stats
    
    # Run main with stats action
    run main "stats" "192.168.1.100"
    
    # Should succeed
    assert_success
}

@test "main function handles reset action" {
    # Mock reset_rate_limit
    # shellcheck disable=SC2317
    reset_rate_limit() {
        return 0
    }
    export -f reset_rate_limit
    
    # Run main with reset action
    run main "reset" "192.168.1.100"
    
    # Should succeed
    assert_success
}

@test "main function handles unknown action" {
    # Run main with unknown action
    run main "unknown" || true
    
    # Should fail and show usage
    assert_failure
}

@test "load_config loads from custom config file" {
    # Create temporary config file
    mkdir -p "${TMP_DIR}"
    local test_config="${TMP_DIR}/test_config.conf"
    echo "export RATE_LIMIT_PER_IP_PER_MINUTE=100" > "${test_config}"
    
    # Run load_config
    run load_config "${test_config}"
    
    # Should succeed
    assert_success
    
    # Cleanup
    rm -f "${test_config}"
}

@test "load_config handles missing config file gracefully" {
    # Run load_config with non-existent file
    run load_config "${TMP_DIR}/nonexistent.conf"
    
    # Should succeed (uses defaults)
    assert_success
}

@test "check_rate_limit_sliding_window uses API key limit when provided" {
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 1
    }
    export -f is_ip_blacklisted
    
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        echo "50"  # Below API key limit of 100
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run check with API key
    run check_rate_limit_sliding_window "192.168.1.100" "/api/notes" "key123"
    
    # Should allow (uses API key limit)
    assert_success
}

@test "check_rate_limit_sliding_window uses endpoint limit when provided" {
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 1
    }
    export -f is_ip_blacklisted
    
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        echo "150"  # Below endpoint limit of 200
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run check with endpoint
    run check_rate_limit_sliding_window "192.168.1.100" "/api/notes"
    
    # Should allow (uses endpoint limit)
    assert_success
}
