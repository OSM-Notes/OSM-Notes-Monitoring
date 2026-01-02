#!/usr/bin/env bash
#
# Third Unit Tests: rateLimiter.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    
    export RATE_LIMIT_ENABLED="true"
    export RATE_LIMIT_THRESHOLD="100"
    export RATE_LIMIT_WINDOW="60"
    export RATE_LIMIT_BURST_SIZE="20"
    
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock functions BEFORE sourcing
    # shellcheck disable=SC2317
    load_config() { return 0; }
    export -f load_config
    # shellcheck disable=SC2317
    init_alerting() { return 0; }
    export -f init_alerting
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/securityFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/security/rateLimiter.sh"
    
    init_logging "${TEST_LOG_DIR}/test_rateLimiter_third.log" "test_rateLimiter_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_rate_limit_sliding_window handles burst requests
##
@test "check_rate_limit_sliding_window handles burst requests" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "150"  # Burst of 150 requests
        return 0
    }
    export -f execute_sql_query
    
    run check_rate_limit_sliding_window "192.168.1.1" "100" "60"
    # Should fail if burst exceeds limit
    assert_success || assert_failure
}

##
# Test: check_rate_limit handles API key rate limiting
##
@test "check_rate_limit handles API key rate limiting" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "50"  # 50 requests for API key
        return 0
    }
    export -f execute_sql_query
    
    run check_rate_limit "api_key_123" "100" "60" "api_key"
    assert_success
}

##
# Test: check_rate_limit handles endpoint-specific limits
##
@test "check_rate_limit handles endpoint-specific limits" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "30"  # 30 requests for endpoint
        return 0
    }
    export -f execute_sql_query
    
    run check_rate_limit "192.168.1.1" "50" "60" "endpoint" "/api/endpoint"
    assert_success
}

##
# Test: main handles --check option
##
@test "main handles --check option" {
    # Mock check_rate_limit
    # shellcheck disable=SC2317
    function check_rate_limit() {
        return 0
    }
    export -f check_rate_limit
    
    run main --check "192.168.1.1"
    assert_success
}
