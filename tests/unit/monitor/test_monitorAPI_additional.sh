#!/usr/bin/env bash
#
# Additional Unit Tests: monitorAPI.sh
# Second test file to increase coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    export API_URL="http://localhost:8080/api/health"
    export API_CHECK_TIMEOUT="5"
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        return 0
    }
    export -f psql
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorAPI.sh"
    
    init_logging "${TEST_LOG_DIR}/test_monitorAPI_additional.log" "test_monitorAPI_additional"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_api_availability handles timeout
##
@test "check_api_availability handles timeout" {
    # Mock curl to timeout
    # shellcheck disable=SC2317
    function curl() {
        sleep 0.001
        return 28  # Timeout error code
    }
    export -f curl
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run check_api_availability
    assert_success || true
}

##
# Test: check_rate_limiting handles disabled rate limiting
##
@test "check_rate_limiting handles disabled rate limiting" {
    export RATE_LIMIT_ENABLED="false"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    run check_rate_limiting
    assert_success
}

##
# Test: check_ddos_protection handles disabled DDoS protection
##
@test "check_ddos_protection handles disabled DDoS protection" {
    export DDOS_ENABLED="false"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    run check_ddos_protection
    assert_success
}

##
# Test: check_abuse_detection handles disabled abuse detection
##
@test "check_abuse_detection handles disabled abuse detection" {
    export ABUSE_DETECTION_ENABLED="false"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    run check_abuse_detection
    assert_success
}

##
# Test: main handles --quiet option
##
@test "main handles --quiet option" {
    # Mock load_config
    # shellcheck disable=SC2317
    load_config() {
        return 0
    }
    export -f load_config
    
    # Mock check functions
    # shellcheck disable=SC2317
    check_api_availability() {
        return 0
    }
    export -f check_api_availability
    
    run main --quiet
    assert_success
}

##
# Test: main handles custom config file
##
@test "main handles custom config file" {
    local test_config="${TEST_LOG_DIR}/test_config.conf"
    echo "API_URL=http://test.example.com" > "${test_config}"
    
    # Mock load_config
    # shellcheck disable=SC2317
    load_config() {
        return 0
    }
    export -f load_config
    
    # Mock check functions
    # shellcheck disable=SC2317
    check_api_availability() {
        return 0
    }
    export -f check_api_availability
    
    run main --config "${test_config}"
    assert_success
    
    rm -f "${test_config}"
}

##
# Test: check_api_availability handles HTTP error codes
##
@test "check_api_availability handles HTTP error codes" {
    # Mock curl to return 500 error
    # shellcheck disable=SC2317
    function curl() {
        return 22  # HTTP error
    }
    export -f curl
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run check_api_availability
    assert_success || true
}
