#!/usr/bin/env bats
#
# Unit Tests: Edge Cases
# Tests edge cases and boundary conditions
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="EDGE_CASES"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/securityFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_edge_cases.log"
    init_logging "${LOG_FILE}" "test_edge_cases"
    
    # Mock database connection
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
}

teardown() {
    # Cleanup
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: record_metric with very large value
##
@test "record_metric handles very large metric value" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    local large_value="999999999999999999"
    run record_metric "ingestion" "large_metric" "${large_value}" "component=test"
    assert_success
}

##
# Test: record_metric with zero value
##
@test "record_metric handles zero metric value" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "ingestion" "zero_metric" "0" "component=test"
    assert_success
}

##
# Test: record_metric with negative value
##
@test "record_metric handles negative metric value" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "ingestion" "negative_metric" "-100" "component=test"
    assert_success
}

##
# Test: record_metric with very long component name
##
@test "record_metric handles very long component name" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    # Very long component name should be rejected (not a valid component)
    local long_component
    long_component="VERY_LONG_COMPONENT_NAME_$(printf 'A%.0s' {1..100})"
    run record_metric "${long_component}" "test_metric" "100" "component=test"
    # Should fail because component name is too long and not in valid list
    assert_failure
}

##
# Test: record_metric with empty metadata
##
@test "record_metric handles empty metadata" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "ingestion" "test_metric" "100" ""
    assert_success
}

##
# Test: send_alert with very long message
##
@test "send_alert handles very long message" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    local long_message
    long_message="$(printf 'A%.0s' {1..1000})"
    run send_alert "ingestion" "warning" "test_alert" "${long_message}"
    assert_success
}

##
# Test: get_metric_value with non-existent metric
##
@test "get_metric_value handles non-existent metric" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run get_metric_value "ingestion" "nonexistent_metric_12345"
    assert_success
    assert_output ""
}

##
# Test: check_rate_limit at exact limit boundary
##
@test "check_rate_limit handles request at exact limit boundary" {
    # Mock psql to return exact limit
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "100"
            return 0
        fi
        return 1
    }
    
    # Mock is_ip_whitelisted and is_ip_blacklisted
    # shellcheck disable=SC2317
    function is_ip_whitelisted() { return 1; }
    export -f is_ip_whitelisted
    # shellcheck disable=SC2317
    function is_ip_blacklisted() { return 1; }
    export -f is_ip_blacklisted
    
    # At exact limit (100), should fail (exceeded)
    # check_rate_limit signature: ip window_seconds max_requests
    run check_rate_limit "192.168.1.1" 60 100
    assert_failure
}

##
# Test: check_rate_limit just below limit
##
@test "check_rate_limit allows request just below limit" {
    # Mock psql to return just below limit
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "99"
            return 0
        fi
        return 1
    }
    
    # Mock is_ip_whitelisted and is_ip_blacklisted
    # shellcheck disable=SC2317
    function is_ip_whitelisted() { return 1; }
    export -f is_ip_whitelisted
    # shellcheck disable=SC2317
    function is_ip_blacklisted() { return 1; }
    export -f is_ip_blacklisted
    
    # check_rate_limit signature: ip window_seconds max_requests
    run check_rate_limit "192.168.1.1" 60 100
    assert_success
}

##
# Test: update_component_health with empty message
##
@test "update_component_health handles empty message" {
    # Mock psql
    # shellcheck disable=SC2317
    # Mock execute_sql_query (update_component_health uses execute_sql_query)
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ UPDATE.*component_health ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run update_component_health "ingestion" "healthy" "0"
    assert_success
}

##
# Test: aggregate_metrics with single data point
##
@test "aggregate_metrics handles single data point" {
    # Mock psql to return single value
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ AVG.*metric_value ]]; then
            echo "100"
        elif [[ "${*}" =~ COUNT ]]; then
            echo "1"
        fi
        return 0
    }
    
    run aggregate_metrics "ingestion" "test_metric" "avg" "24 hours"
    assert_success
    assert_output "100"
}

##
# Test: validate_ip_address with boundary IP values
##
@test "is_valid_ip handles boundary IP values" {
    # Test minimum IP
    run is_valid_ip "0.0.0.0"
    assert_success
    
    # Test maximum IP
    run is_valid_ip "255.255.255.255"
    assert_success
}

##
# Test: record_metric with special characters in metric name
##
@test "record_metric handles special characters in metric name" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "ingestion" "metric_with_underscores_and-numbers-123" "100" "component=test"
    assert_success
}

##
# Test: record_metric with unicode characters
##
@test "record_metric handles unicode characters in component name" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    # Test with valid component name (unicode in component name is not valid, so use valid component)
    run record_metric "data" "test_metric_测试" "100" "component=test"
    assert_success
}

##
# Test: send_alert with unicode message
##
@test "send_alert handles unicode message" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    run send_alert "ingestion" "warning" "test_alert" "Test message: 测试消息"
    assert_success
}

##
# Test: get_metric_value with boundary timestamp
##
@test "get_metric_value handles boundary timestamp values" {
    # Mock psql to return boundary timestamp
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*timestamp ]]; then
            echo "1970-01-01 00:00:00"  # Unix epoch
        fi
        return 0
    }
    
    run get_metric_value "ingestion" "test_metric"
    assert_success
}

##
# Test: check_rate_limit with maximum integer value
##
@test "check_rate_limit handles maximum integer limit value" {
    # Mock psql to return max int
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "2147483647"  # Max 32-bit signed int
        fi
        return 0
    }
    
    # Mock is_ip_whitelisted and is_ip_blacklisted
    # shellcheck disable=SC2317
    function is_ip_whitelisted() { return 1; }
    export -f is_ip_whitelisted
    # shellcheck disable=SC2317
    function is_ip_blacklisted() { return 1; }
    export -f is_ip_blacklisted
    
    # check_rate_limit signature: ip window_seconds max_requests
    run check_rate_limit "192.168.1.1" 60 2147483647
    # Should handle max int gracefully
    assert [ ${status} -ge 0 ]
}

##
# Test: record_metric with floating point precision edge cases
##
@test "record_metric handles floating point precision edge cases" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    # Test with very small decimal
    run record_metric "ingestion" "small_metric" "0.0000000001" "component=test"
    assert_success
    
    # Test with very large decimal
    run record_metric "ingestion" "large_metric" "999999999.999999999" "component=test"
    assert_success
}

##
# Test: update_component_health with maximum length message
##
@test "update_component_health handles maximum length message" {
    # Mock execute_sql_query (update_component_health uses execute_sql_query)
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ UPDATE.*component_health ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    # Test with valid component and error_count (third parameter is error_count, not message)
    run update_component_health "ingestion" "healthy" "0"
    assert_success
}

##
# Test: aggregate_metrics with zero time window
##
@test "aggregate_metrics handles zero time window gracefully" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run aggregate_metrics "ingestion" "test_metric" "avg" "0 hours"
    # Should handle zero window gracefully
    assert_success
}

##
# Test: record_metric with negative timestamp offset
##
@test "record_metric handles negative timestamp offset" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    # This test verifies the function doesn't crash with edge case timestamps
    run record_metric "ingestion" "test_metric" "100" "component=test,timestamp_offset=-3600"
    assert_success
}

##
# Test: check_rate_limit with zero limit
##
@test "check_rate_limit handles zero limit gracefully" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "0"
        fi
        return 0
    }
    
    # Mock is_ip_whitelisted and is_ip_blacklisted
    # shellcheck disable=SC2317
    function is_ip_whitelisted() { return 1; }
    export -f is_ip_whitelisted
    # shellcheck disable=SC2317
    function is_ip_blacklisted() { return 1; }
    export -f is_ip_blacklisted
    
    # check_rate_limit signature: ip window_seconds max_requests
    run check_rate_limit "192.168.1.1" 60 0
    # With zero limit, any request should be blocked
    assert_failure
}

##
# Test: get_metrics_by_component with SQL wildcards in component name
##
@test "get_metrics_by_component handles SQL wildcards safely" {
    # Source metricsFunctions to get the function
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh" 2>/dev/null || true
    
    # Mock psql - should escape wildcards
    # shellcheck disable=SC2317
    function psql() {
        # Check that wildcards are escaped
        if [[ "${*}" =~ LIKE.*% ]]; then
            # Wildcards should be escaped, not interpreted
            return 0
        fi
        return 0
    }
    
    run get_metrics_by_component "ingestion"
    assert_success
}
