#!/usr/bin/env bash
#
# Unit Tests: rateLimiter.sh
# Tests rate limiting functionality
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

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
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/security/rateLimiter.sh" 2>/dev/null || true
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
    
    # Track if record_security_event was called
    local alert_file="${TMP_DIR}/.rate_limit_result"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "rate_limit" ]] && [[ "${4}" == *"exceeded"* ]]; then
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
    local delete_called=false
    
    # Mock psql to track DELETE calls
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]] && [[ "${*}" == *"192.168.1.100"* ]]; then
            delete_called=true
        fi
        return 0
    }
    export -f psql
    
    # Run reset
    run reset_rate_limit "192.168.1.100" ""
    
    # Should succeed and call DELETE
    assert_success
    assert_equal "true" "${delete_called}"
}

@test "reset_rate_limit handles endpoint parameter" {
    local delete_called=false
    
    # Mock psql to track DELETE calls with endpoint
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]] && [[ "${*}" == *"/api/notes"* ]]; then
            delete_called=true
        fi
        return 0
    }
    export -f psql
    
    # Run reset with endpoint
    run reset_rate_limit "192.168.1.100" "/api/notes"
    
    # Should succeed and include endpoint in DELETE
    assert_success
    assert_equal "true" "${delete_called}"
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
    
    export -f is_ip_whitelisted is_ip_blacklisted psql record_security_event
    
    # Run main with check action
    run main "check" "192.168.1.100" "" "" || true
    
    # Should output RATE_LIMITED
    assert_failure
    assert_output "RATE_LIMITED"
}

@test "main function record action calls record_request" {
    local record_called=false
    
    # Mock record_security_event to track calls
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "rate_limit" ]] && [[ "${2}" == "192.168.1.100" ]]; then
            record_called=true
        fi
        return 0
    }
    export -f record_security_event
    
    # Run main with record action
    run main "record" "192.168.1.100" "/api/notes" ""
    
    # Should succeed
    assert_success
    assert_equal "true" "${record_called}"
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
    local reset_called=false
    
    # Mock psql to track DELETE
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]]; then
            reset_called=true
        fi
        return 0
    }
    export -f psql
    
    # Run main with reset action
    run main "reset" "192.168.1.100" ""
    
    # Should succeed
    assert_success
    assert_equal "true" "${reset_called}"
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

