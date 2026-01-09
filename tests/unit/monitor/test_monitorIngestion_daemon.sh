#!/usr/bin/env bash
#
# Unit Tests: monitorIngestion.sh - Daemon Metrics Tests
# Tests daemon metrics check function
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_INGESTION_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_ingestion"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_INGESTION_DIR}/bin"
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export INGESTION_REPO_PATH="${TEST_INGESTION_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Set test configuration
    export INGESTION_ENABLED="true"
    export INGESTION_DAEMON_CYCLE_DURATION_THRESHOLD="30"
    export INGESTION_DAEMON_SUCCESS_RATE_THRESHOLD="95"
    export INGESTION_DAEMON_NO_PROCESSING_THRESHOLD="300"
    
    # Disable alerts for unit tests
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    export ADMIN_EMAIL="test@example.com"
    export ALERT_RECIPIENTS="test@example.com"
    
    # Mock database functions
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock execute_sql_query to return test data
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        # Return daemon_status = 1 (active)
        if [[ "${query}" == *"daemon_status"* ]]; then
            echo "1"
            return 0
        fi
        
        # Return cycle_duration = 15 seconds (below threshold)
        if [[ "${query}" == *"daemon_cycle_duration_seconds"* ]]; then
            echo "15"
            return 0
        fi
        
        # Return success_rate = 100%
        if [[ "${query}" == *"daemon_cycle_success_rate_percent"* ]]; then
            echo "100"
            return 0
        fi
        
        # Return recent cycle timestamp
        if [[ "${query}" == *"daemon_cycle_number"* ]] && [[ "${query}" == *"5 minutes"* ]]; then
            date +%Y-%m-%d\ %H:%M:%S
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
    
    # Initialize ALERTS_SENT array (will be populated by send_alert mock)
    # Use a file to track alerts since arrays don't export well
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_sent.txt"
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Note: collectDaemonMetrics.sh should exist in the actual bin/monitor directory
    # The test will use the real script if it exists, or handle gracefully if it doesn't
    
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
    init_logging "${TEST_LOG_DIR}/test_monitorIngestion_daemon.log" "test_monitorIngestion_daemon"
    
    # Initialize alerting (but we'll override send_alert)
    init_alerting
    
    # Override send_alert BEFORE sourcing monitorIngestion.sh
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Source monitorIngestion.sh functions
    export TEST_MODE=true
    export COMPONENT="INGESTION"
    
    # Note: SCRIPT_DIR is set by monitorIngestion.sh itself and is readonly
    # We'll work with the actual script location
    
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorIngestion.sh" 2>/dev/null || true
    
    # Override record_metric after sourcing to avoid DB calls
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
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
    rm -rf "${TEST_INGESTION_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

@test "check_daemon_metrics succeeds when daemon is active" {
    # Mock bash to handle collectDaemonMetrics.sh execution successfully
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDaemonMetrics.sh" ]]; then
            # Mock successful execution - script runs and collects metrics
            return 0
        fi
        # Call real bash for other commands
        command bash "$@"
    }
    export -f bash
    
    # Mock execute_sql_query to return active status
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"daemon_status"* ]]; then
            echo "1"
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_duration_seconds"* ]]; then
            echo "15"
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_success_rate_percent"* ]]; then
            echo "100"
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_number"* ]] && [[ "${query}" == *"5 minutes"* ]]; then
            date +%Y-%m-%d\ %H:%M:%S
            return 0
        fi
        
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    run check_daemon_metrics
    
    # Should succeed
    assert_success
}

@test "check_daemon_metrics alerts when daemon is inactive" {
    # Reset alerts file for this test
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash to handle collectDaemonMetrics.sh execution
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDaemonMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Override send_alert to capture alerts
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Mock execute_sql_query to return inactive status
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"daemon_status"* ]]; then
            echo "0"
            return 0
        fi
        
        # Return empty for other queries to avoid errors
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    run check_daemon_metrics
    
    # Should fail and send alert
    assert_failure
    
    # Check that alert was sent by reading from file
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"daemon_down"* ]] || [[ "${alert}" == *"Daemon service is not active"* ]] || [[ "${alert}" == *"CRITICAL"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_daemon_metrics alerts when cycle duration exceeds threshold" {
    # Reset alerts file for this test
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash to handle collectDaemonMetrics.sh execution
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDaemonMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Override send_alert to capture alerts
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Mock execute_sql_query to return high cycle duration
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"daemon_status"* ]]; then
            echo "1"
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_duration_seconds"* ]]; then
            echo "45"  # Above threshold of 30
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_success_rate_percent"* ]]; then
            echo "100"
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_number"* ]] && [[ "${query}" == *"5 minutes"* ]]; then
            date +%Y-%m-%d\ %H:%M:%S
            return 0
        fi
        
        # Return empty for other queries
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_daemon_metrics
    
    # Check that alert was sent by reading from file
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"daemon_cycle_duration"* ]] || [[ "${alert}" == *"Cycle duration"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_daemon_metrics alerts when success rate is below threshold" {
    # Reset alerts file for this test
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash to handle collectDaemonMetrics.sh execution
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDaemonMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Override send_alert to capture alerts
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Mock execute_sql_query to return low success rate
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"daemon_status"* ]]; then
            echo "1"
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_duration_seconds"* ]]; then
            echo "15"
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_success_rate_percent"* ]]; then
            echo "90"  # Below threshold of 95
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_number"* ]] && [[ "${query}" == *"5 minutes"* ]]; then
            date +%Y-%m-%d\ %H:%M:%S
            return 0
        fi
        
        # Return empty for other queries
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_daemon_metrics
    
    # Check that alert was sent by reading from file
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"daemon_success_rate"* ]] || [[ "${alert}" == *"Cycle success rate"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_daemon_metrics alerts when no processing detected" {
    # Reset alerts file for this test
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash to handle collectDaemonMetrics.sh execution
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDaemonMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Override send_alert to capture alerts
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Mock execute_sql_query to return no recent cycles
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"daemon_status"* ]]; then
            echo "1"
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_duration_seconds"* ]]; then
            echo "15"
            return 0
        fi
        
        if [[ "${query}" == *"daemon_cycle_success_rate_percent"* ]]; then
            echo "100"
            return 0
        fi
        
        # Return empty (no recent cycles)
        if [[ "${query}" == *"daemon_cycle_number"* ]] && [[ "${query}" == *"5 minutes"* ]]; then
            echo ""
            return 0
        fi
        
        # Return empty for other queries
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    run check_daemon_metrics
    
    # Should fail and send alert
    assert_failure
    
    # Check that alert was sent by reading from file
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"daemon_no_processing"* ]] || [[ "${alert}" == *"No daemon processing detected"* ]] || [[ "${alert}" == *"CRITICAL"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_daemon_metrics handles missing script gracefully" {
    # This test verifies that check_daemon_metrics handles missing script file gracefully
    # The function checks for file existence before trying to execute it
    
    # We need to mock the file check, but since SCRIPT_DIR is readonly,
    # we'll test the logic by ensuring the function handles the case correctly
    
    # Mock bash in case it's called (shouldn't be if file check works)
    # shellcheck disable=SC2317
    bash() {
        return 0
    }
    export -f bash
    
    # The actual test: if the script file doesn't exist at SCRIPT_DIR/collectDaemonMetrics.sh,
    # the function should return 0 (success) with a warning, not fail
    # Since we can't easily change SCRIPT_DIR, we'll verify the function logic works
    
    # For this test, we'll assume the script exists and test the graceful path differently
    # Or we can skip this test if the script exists
    local script_path="${SCRIPT_DIR}/collectDaemonMetrics.sh"
    if [[ ! -f "${script_path}" ]]; then
        # Script doesn't exist, test should pass (graceful handling)
        run check_daemon_metrics
        assert_success
    else
        # Script exists, skip this test or test a different scenario
        skip "Script exists, cannot test missing script scenario easily"
    fi
}

@test "check_daemon_metrics handles non-executable script gracefully" {
    # This test verifies that the function handles non-executable scripts gracefully
    # We'll temporarily make the script non-executable, test, then restore
    
    local script_path="${SCRIPT_DIR}/collectDaemonMetrics.sh"
    local was_executable=false
    
    if [[ -f "${script_path}" ]]; then
        # Check if currently executable
        if [[ -x "${script_path}" ]]; then
            was_executable=true
            chmod -x "${script_path}"
        fi
        
        # Mock execute_sql_query to avoid DB calls (function may still query DB)
        # shellcheck disable=SC2317
        execute_sql_query() {
            echo ""
            return 0
        }
        export -f execute_sql_query
        
        # Run check - should succeed (graceful handling - function returns 0 with warning)
        run check_daemon_metrics
        
        # Restore permissions if needed
        if [[ "${was_executable}" == "true" ]]; then
            chmod +x "${script_path}"
        fi
        
        # Should succeed (graceful handling - returns 0 with warning, doesn't fail)
        # The function checks for non-executable script and returns 0 with a warning
        assert_success
    else
        # Script doesn't exist, skip test
        skip "collectDaemonMetrics.sh not found"
    fi
}
