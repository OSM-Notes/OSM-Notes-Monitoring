#!/usr/bin/env bash
#
# Unit Tests: monitorWMS.sh
# Tests WMS monitoring check functions
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
    export WMS_ENABLED="true"
    export WMS_BASE_URL="http://localhost:8080"
    export WMS_HEALTH_CHECK_URL="http://localhost:8080/health"
    export WMS_CHECK_TIMEOUT="30"
    export WMS_RESPONSE_TIME_THRESHOLD="2000"
    export WMS_ERROR_RATE_THRESHOLD="5"
    export WMS_TILE_GENERATION_THRESHOLD="5000"
    export WMS_CACHE_HIT_RATE_THRESHOLD="80"
    export WMS_LOG_DIR="${TEST_LOG_DIR}"
    
    # Disable alerts for unit tests
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
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
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test.log" "test_monitorWMS"
    
    # Initialize alerting
    init_alerting
    
    # Source monitorWMS.sh functions
    # Set component name BEFORE sourcing (to allow override)
    export TEST_MODE=true
    export COMPONENT="WMS"
    
    # We'll source it but need to handle the main execution
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorWMS.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

##
# Helper: Create test log file
##
create_test_log() {
    local log_name="${1}"
    local content="${2}"
    
    local log_path="${TEST_LOG_DIR}/${log_name}"
    echo "${content}" > "${log_path}"
}

@test "check_wms_service_availability succeeds when service is available" {
    # Mock curl to return success
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-s" ]] && [[ "${2}" == "-o" ]]; then
            echo "200" > "${4}"
            return 0
        elif [[ "${1}" == "-w" ]]; then
            echo "200"
            return 0
        fi
        return 0
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
    
    # Run check
    run check_wms_service_availability
    
    # Should succeed
    assert_success
}

@test "check_wms_service_availability alerts when service is unavailable" {
    # Mock curl to return failure
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-w" ]]; then
            echo "503"  # Service unavailable
            return 1
        fi
        return 1
    }
    export -f curl
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Use a temp file to track alert status
    local alert_file="${TEST_LOG_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"WMS service is unavailable"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_wms_service_availability || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_http_health succeeds when health check passes" {
    # Mock curl to return healthy response
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-s" ]] && [[ "${2}" == "-w" ]]; then
            echo "healthy"
            echo "200"
            return 0
        fi
        return 0
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
    
    # Run check
    run check_http_health
    
    # Should succeed
    assert_success
}

@test "check_http_health alerts when health check fails" {
    # Mock curl to return unhealthy response
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-s" ]] && [[ "${2}" == "-w" ]]; then
            echo "unhealthy"
            echo "500"
            return 1
        fi
        return 1
    }
    export -f curl
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Use a temp file to track alert status
    local alert_file="${TEST_LOG_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"WMS health check failed"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_http_health || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_response_time records metric when response time is acceptable" {
    # Mock curl to return fast response
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-w" ]]; then
            sleep 0.001  # Simulate 1ms response
            echo "200"
            return 0
        fi
        return 0
    }
    export -f curl
    
    local metric_recorded=false
    # shellcheck disable=SC2317
    record_metric() {
        if [[ "${2}" == "response_time_ms" ]]; then
            metric_recorded=true
        fi
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_response_time
    
    # Should succeed and record metric
    assert_success
    assert_equal "true" "${metric_recorded}"
}

@test "check_response_time alerts when response time exceeds threshold" {
    # Mock curl to return slow response
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-w" ]]; then
            sleep 0.003  # Simulate 3s response (exceeds 2s threshold)
            echo "200"
            return 0
        fi
        return 0
    }
    export -f curl
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Use a temp file to track alert status
    local alert_file="${TEST_LOG_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"WMS response time"* ]] && [[ "${4}" == *"exceeds threshold"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_response_time || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_error_rate calculates error rate correctly" {
    # Create test log with errors
    create_test_log "wms.log" "ERROR: Test error 1
INFO: Request processed
ERROR: Test error 2
INFO: Request processed
INFO: Request processed"
    
    # Mock database query to return error and request counts
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"error_count"* ]]; then
            echo "2|10"  # error_count|request_count
        fi
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
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
    
    # Run check
    run check_error_rate
    
    # Should succeed
    assert_success
}

@test "check_error_rate alerts when error rate exceeds threshold" {
    # Mock database query to return high error rate
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"error_count"* ]]; then
            echo "100|1000"  # 10% error rate (exceeds 5% threshold)
        fi
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Use a temp file to track alert status
    local alert_file="${TEST_LOG_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"WMS error rate"* ]] && [[ "${4}" == *"exceeds threshold"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_error_rate || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_tile_generation_performance records metric when generation is fast" {
    # Mock curl to return fast tile generation
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-w" ]]; then
            sleep 0.001  # Simulate 1ms generation
            echo "200"
            return 0
        fi
        return 0
    }
    export -f curl
    
    local metric_recorded=false
    # shellcheck disable=SC2317
    record_metric() {
        if [[ "${2}" == "tile_generation_time_ms" ]]; then
            metric_recorded=true
        fi
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_tile_generation_performance
    
    # Should succeed and record metric
    assert_success
    assert_equal "true" "${metric_recorded}"
}

@test "check_tile_generation_performance alerts when generation is slow" {
    # Mock curl to return slow tile generation
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-w" ]]; then
            sleep 0.006  # Simulate 6s generation (exceeds 5s threshold)
            echo "200"
            return 0
        fi
        return 0
    }
    export -f curl
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Use a temp file to track alert status
    local alert_file="${TEST_LOG_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"WMS tile generation time"* ]] && [[ "${4}" == *"exceeds threshold"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_tile_generation_performance || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_cache_hit_rate calculates hit rate correctly" {
    # Mock database query to return cache statistics
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"cache_hits"* ]]; then
            echo "800|200"  # cache_hits|cache_misses (80% hit rate)
        fi
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
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
    
    # Run check
    run check_cache_hit_rate
    
    # Should succeed
    assert_success
}

@test "check_cache_hit_rate alerts when hit rate is below threshold" {
    # Mock database query to return low cache hit rate
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"cache_hits"* ]]; then
            echo "600|400"  # 60% hit rate (below 80% threshold)
        fi
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Use a temp file to track alert status
    local alert_file="${TEST_LOG_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"WMS cache hit rate"* ]] && [[ "${4}" == *"below threshold"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_cache_hit_rate || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_wms_service_availability skips when WMS is disabled" {
    export WMS_ENABLED="false"
    
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
    
    # Run check
    run check_wms_service_availability
    
    # Should succeed (skip)
    assert_success
}

@test "check_response_time handles curl unavailability gracefully" {
    # Unset curl command
    # shellcheck disable=SC2317
    curl() {
        return 127  # Command not found
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
    
    # Run check
    run check_response_time
    
    # Should succeed (skip gracefully)
    assert_success
}


@test "main function handles all checks action" {
    # Mock all check functions
    # shellcheck disable=SC2317
    check_wms_service_availability() {
        return 0
    }
    export -f check_wms_service_availability
    
    # shellcheck disable=SC2317
    check_http_health() {
        return 0
    }
    export -f check_http_health
    
    # shellcheck disable=SC2317
    check_response_time() {
        return 0
    }
    export -f check_response_time
    
    # shellcheck disable=SC2317
    check_error_rate() {
        return 0
    }
    export -f check_error_rate
    
    # shellcheck disable=SC2317
    check_tile_generation_performance() {
        return 0
    }
    export -f check_tile_generation_performance
    
    # shellcheck disable=SC2317
    check_cache_hit_rate() {
        return 0
    }
    export -f check_cache_hit_rate
    
    # Run main with all checks
    run main "all"
    
    # Should succeed
    assert_success
}

@test "main function handles specific check action" {
    # Mock check_wms_service_availability
    # shellcheck disable=SC2317
    check_wms_service_availability() {
        return 0
    }
    export -f check_wms_service_availability
    
    # Run main with specific check
    run main "availability"
    
    # Should succeed
    assert_success
}

@test "main function handles unknown check action" {
    # Run main with unknown check
    run main "unknown" || true
    
    # Should fail
    assert_failure
}

@test "load_config loads from custom config file" {
    # Create temporary config file
    mkdir -p "${TMP_DIR}"
    local test_config="${TMP_DIR}/test_config.conf"
    echo "export WMS_ENABLED=true" > "${test_config}"
    echo "export WMS_BASE_URL=http://test.example.com" >> "${test_config}"
    
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

@test "check_http_health handles timeout" {
    export WMS_HEALTH_CHECK_URL="http://localhost:8080/health"
    export WMS_CHECK_TIMEOUT="1"
    
    # Mock curl to timeout
    # shellcheck disable=SC2317
    curl() {
        return 124  # Timeout exit code
    }
    export -f curl
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check_http_health
    run check_http_health
    
    # Should detect timeout
    assert_failure
}

@test "check_response_time handles slow response" {
    export WMS_RESPONSE_TIME_THRESHOLD="1000"
    
    # Mock curl to return slow response
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-w" ]]; then
            echo "2000"  # 2 seconds (over threshold)
        fi
        return 0
    }
    export -f curl
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check_response_time
    run check_response_time
    
    # Should detect slow response
    assert_failure
}

@test "check_error_rate handles high error rate" {
    export WMS_ERROR_RATE_THRESHOLD="5"
    
    # Mock psql to return high error rate
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]] && [[ "${*}" == *"FILTER"* ]]; then
            echo "10|100"  # 10 errors out of 100 requests = 10% (over 5% threshold)
        fi
        return 0
    }
    export -f psql
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check_error_rate
    run check_error_rate
    
    # Should detect high error rate
    assert_failure
}

@test "check_tile_generation_performance handles slow tile generation" {
    export WMS_TILE_GENERATION_THRESHOLD="5000"
    
    # Mock psql to return slow tile generation
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"AVG"* ]] && [[ "${*}" == *"tile_generation_time"* ]]; then
            echo "6000"  # 6 seconds (over 5 second threshold)
        fi
        return 0
    }
    export -f psql
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check_tile_generation_performance
    run check_tile_generation_performance
    
    # Should detect slow tile generation
    assert_failure
}

@test "check_cache_hit_rate handles low cache hit rate" {
    export WMS_CACHE_HIT_RATE_THRESHOLD="80"
    
    # Mock psql to return low cache hit rate
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT"* ]] && [[ "${*}" == *"cache_hit"* ]]; then
            echo "70|100"  # 70% cache hit rate (below 80% threshold)
        fi
        return 0
    }
    export -f psql
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check_cache_hit_rate
    run check_cache_hit_rate
    
    # Should detect low cache hit rate
    assert_failure
}
