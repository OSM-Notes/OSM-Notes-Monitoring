#!/usr/bin/env bash
#
# Unit Tests: monitorInfrastructure.sh - Advanced System Metrics Tests
# Tests advanced system metrics check function
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
    export INFRASTRUCTURE_ENABLED="true"
    export INFRASTRUCTURE_SWAP_THRESHOLD="50"
    export INFRASTRUCTURE_LOAD_THRESHOLD_MULTIPLIER="2"
    
    # Disable alerts for unit tests
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    export ADMIN_EMAIL="test@example.com"
    export ALERT_RECIPIENTS="test@example.com"
    
    # Use a file to track alerts
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_sent.txt"
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    export ALERTS_FILE
    
    # Mock execute_sql_query to return test data
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        # Return load average = 1.0 (below threshold for 4 CPUs = 8.0)
        if [[ "${query}" == *"system_load_average_1min"* ]]; then
            echo "1.0"
            return 0
        fi
        
        # Return CPU count = 4
        if [[ "${query}" == *"system_cpu_count"* ]]; then
            echo "4"
            return 0
        fi
        
        # Return swap usage = 10% (below threshold)
        if [[ "${query}" == *"system_swap_usage_percent"* ]]; then
            echo "10"
            return 0
        fi
        
        return 0
    }
    export -f execute_sql_query
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        echo "" 2>/dev/null
        return 0
    }
    export -f psql
    
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
    init_logging "${TEST_LOG_DIR}/test_monitorInfrastructure_system.log" "test_monitorInfrastructure_system"
    
    # Initialize alerting (but we'll override send_alert)
    init_alerting
    
    # Override send_alert BEFORE sourcing monitorInfrastructure.sh
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Source monitorInfrastructure.sh functions
    export TEST_MODE=true
    export COMPONENT="INFRASTRUCTURE"
    
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorInfrastructure.sh" 2>/dev/null || true
    
    # Ensure send_alert is still our mock after sourcing
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

@test "check_advanced_system_metrics succeeds when all metrics are healthy" {
    # Mock bash to handle collectSystemMetrics.sh execution
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectSystemMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Run check
    run check_advanced_system_metrics
    
    # Should succeed
    assert_success
}

@test "check_advanced_system_metrics alerts when load average exceeds threshold" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectSystemMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Mock execute_sql_query to return high load average
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"system_load_average_1min"* ]]; then
            echo "10.0"  # Above threshold for 4 CPUs (2x4=8.0)
            return 0
        fi
        
        if [[ "${query}" == *"system_cpu_count"* ]]; then
            echo "4"
            return 0
        fi
        
        if [[ "${query}" == *"system_swap_usage_percent"* ]]; then
            echo "10"
            return 0
        fi
        
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_advanced_system_metrics
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"system_load_high"* ]] || [[ "${alert}" == *"Load average"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_advanced_system_metrics alerts when swap usage exceeds threshold" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectSystemMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Mock execute_sql_query to return high swap usage
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"system_load_average_1min"* ]]; then
            echo "1.0"
            return 0
        fi
        
        if [[ "${query}" == *"system_cpu_count"* ]]; then
            echo "4"
            return 0
        fi
        
        if [[ "${query}" == *"system_swap_usage_percent"* ]]; then
            echo "60"  # Above threshold of 50
            return 0
        fi
        
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_advanced_system_metrics
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"system_swap_high"* ]] || [[ "${alert}" == *"Swap usage"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_advanced_system_metrics handles missing script gracefully" {
    # Mock test to check if script file exists check works
    # The function checks for script existence, so we'll test that path
    
    # Mock bash
    # shellcheck disable=SC2317
    bash() {
        return 0
    }
    export -f bash
    
    # The actual test: if the script file doesn't exist at SCRIPT_DIR/collectSystemMetrics.sh,
    # the function should return 0 (success) with a warning, not fail
    local script_path="${SCRIPT_DIR}/collectSystemMetrics.sh"
    if [[ ! -f "${script_path}" ]]; then
        # Script doesn't exist, test should pass (graceful handling)
        run check_advanced_system_metrics
        assert_success
    else
        # Script exists, skip this test or test a different scenario
        skip "collectSystemMetrics.sh exists, cannot test missing script scenario easily"
    fi
}

@test "check_advanced_system_metrics handles non-executable script gracefully" {
    # This test verifies that the function handles non-executable scripts gracefully
    local script_path="${SCRIPT_DIR}/collectSystemMetrics.sh"
    local was_executable=false
    
    if [[ -f "${script_path}" ]]; then
        # Check if currently executable
        if [[ -x "${script_path}" ]]; then
            was_executable=true
            chmod -x "${script_path}"
        fi
        
        # Mock bash
        # shellcheck disable=SC2317
        bash() {
            return 0
        }
        export -f bash
        
        # Mock execute_sql_query
        # shellcheck disable=SC2317
        execute_sql_query() {
            echo ""
            return 0
        }
        export -f execute_sql_query
        
        # Run check - should succeed (graceful handling)
        run check_advanced_system_metrics
        
        # Restore permissions if needed
        if [[ "${was_executable}" == "true" ]]; then
            chmod +x "${script_path}"
        fi
        
        # Should succeed (graceful handling - returns 0 with warning)
        assert_success
    else
        # Script doesn't exist, skip test
        skip "collectSystemMetrics.sh not found"
    fi
}
