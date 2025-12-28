#!/usr/bin/env bash
#
# Integration Tests: Alert Delivery for Analytics
# Tests that alerts are properly stored and delivered when analytics issues are detected
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
TEST_COMPONENT="ANALYTICS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    
    # Disable alert deduplication for testing
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_analytics_alert_delivery.log"
    init_logging "${LOG_FILE}" "test_analytics_alert_delivery"
    
    # Initialize alerting
    init_alerting
    
    # Clean test database
    clean_test_database
}

teardown() {
    # Clean up test alerts
    clean_test_database
    
    # Clean up test log files
    rm -rf "${TEST_LOG_DIR}"
}

##
# Helper function to count alerts in database
##
count_alerts() {
    local component="${1}"
    local alert_level="${2:-}"
    local alert_type="${3:-}"
    
    local query="SELECT COUNT(*) FROM alerts WHERE component = '${component}'"
    
    if [[ -n "${alert_level}" ]]; then
        query="${query} AND alert_level = '${alert_level}'"
    fi
    
    if [[ -n "${alert_type}" ]]; then
        query="${query} AND alert_type = '${alert_type}'"
    fi
    
    run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]' || echo "0"
}

##
# Helper function to get latest alert message
##
get_latest_alert_message() {
    local component="${1}"
    
    local query="SELECT message FROM alerts 
                 WHERE component = '${component}' 
                 ORDER BY created_at DESC 
                 LIMIT 1;"
    
    run_sql_query "${query}" 2>/dev/null | head -1 || echo ""
}

@test "Alert is stored in database when send_alert is called" {
    skip_if_database_not_available
    
    # Send a test alert
    send_alert "${TEST_COMPONENT}" "WARNING" "test_alert" "Test alert message"
    
    # Wait a moment for database write
    sleep 1
    
    # Verify alert was stored
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "1" "${alert_count}"
}

@test "ETL scripts found alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "etl_scripts_found" "Low number of ETL scripts found: 1 (threshold: 2)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "etl_scripts_found")
    
    assert_equal "1" "${alert_count}"
}

@test "ETL execution age alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "etl_last_execution_age" "Last ETL execution is 7200s old (threshold: 3600s)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "etl_last_execution_age")
    
    assert_equal "1" "${alert_count}"
}

@test "ETL error count alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "etl_error_count" "ETL job errors detected: 5 errors in last 24 hours"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "etl_error_count")
    
    assert_equal "1" "${alert_count}"
}

@test "ETL failure count alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "etl_failure_count" "ETL job failures detected: 2 failures in last 24 hours"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "etl_failure_count")
    
    assert_equal "1" "${alert_count}"
}

@test "ETL duration alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "etl_duration" "Long-running ETL job detected: script.sh has been running for 7200s (threshold: 3600s)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "etl_duration")
    
    assert_equal "1" "${alert_count}"
}

@test "ETL average duration alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "etl_avg_duration" "Average ETL processing duration exceeded: 2400s (threshold: 1800s)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "etl_avg_duration")
    
    assert_equal "1" "${alert_count}"
}

@test "ETL max duration alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "etl_max_duration" "Maximum ETL processing duration exceeded: 9000s (threshold: 7200s)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "etl_max_duration")
    
    assert_equal "1" "${alert_count}"
}

@test "Data warehouse freshness alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "data_warehouse_freshness" "Data warehouse freshness exceeded: 7200s (threshold: 3600s)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "data_warehouse_freshness")
    
    assert_equal "1" "${alert_count}"
}

@test "Data warehouse recent updates alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "data_warehouse_recent_updates" "No recent updates in data warehouse in the last hour"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "data_warehouse_recent_updates")
    
    assert_equal "1" "${alert_count}"
}

@test "Data mart update age alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "data_mart_update_age" "Data mart update age exceeded: 7200s (threshold: 3600s)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "data_mart_update_age")
    
    assert_equal "1" "${alert_count}"
}

@test "Data mart recent updates alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "data_mart_recent_updates" "No recent updates in data mart in the last hour"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "data_mart_recent_updates")
    
    assert_equal "1" "${alert_count}"
}

@test "Data mart stale count alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "data_mart_stale_count" "Data mart staleness detected: 3 mart(s) exceed freshness threshold"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "data_mart_stale_count")
    
    assert_equal "1" "${alert_count}"
}

@test "Data mart failure alert is stored with ERROR level" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "ERROR" "data_mart_failure" "Data mart update failures detected: 2 mart(s) have update failures"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "error" "data_mart_failure")
    
    assert_equal "1" "${alert_count}"
}

@test "Data mart average update age alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "data_mart_avg_update_age" "Average data mart update age exceeded: 2400s (threshold: 1800s)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "data_mart_avg_update_age")
    
    assert_equal "1" "${alert_count}"
}

@test "Slow queries alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "slow_queries" "Slow queries detected: 5 queries exceed 1000ms (max: 5000ms, avg: 2000ms)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "slow_queries")
    
    assert_equal "1" "${alert_count}"
}

@test "Slow query alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "slow_query" "Slow query detected: 2000ms (query: SELECT * FROM large_table...)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "slow_query")
    
    assert_equal "1" "${alert_count}"
}

@test "Query average time alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "query_avg_time" "Average query time exceeded: 800ms (threshold: 500ms)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "query_avg_time")
    
    assert_equal "1" "${alert_count}"
}

@test "Query max time alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "query_max_time" "Maximum query time exceeded: 6000ms (threshold: 5000ms)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "query_max_time")
    
    assert_equal "1" "${alert_count}"
}

@test "Database size alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "database_size" "Database size exceeded: 120GB (threshold: 100GB)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "database_size")
    
    assert_equal "1" "${alert_count}"
}

@test "Table size alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "table_size" "Largest table size exceeded: large_table - 12GB (threshold: 10GB)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "table_size")
    
    assert_equal "1" "${alert_count}"
}

@test "Disk usage WARNING alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "disk_usage" "High disk usage: 87% (available: 13GB)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "warning" "disk_usage")
    
    assert_equal "1" "${alert_count}"
}

@test "Disk usage CRITICAL alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "CRITICAL" "disk_usage" "Critical disk usage: 92% (available: 8GB)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "critical" "disk_usage")
    
    assert_equal "1" "${alert_count}"
}

@test "Database connection CRITICAL alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "CRITICAL" "database_connection" "Database connection failed"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "critical" "database_connection")
    
    assert_equal "1" "${alert_count}"
}

@test "Unused index INFO alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "INFO" "unused_index_count" "Found 8 potentially unused indexes - consider reviewing for optimization"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "info" "unused_index_count")
    
    assert_equal "1" "${alert_count}"
}

@test "Multiple analytics alert types are stored separately" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "etl_scripts_found" "Low number of ETL scripts found"
    sleep 1
    send_alert "${TEST_COMPONENT}" "WARNING" "data_warehouse_freshness" "Data warehouse freshness exceeded"
    sleep 1
    send_alert "${TEST_COMPONENT}" "CRITICAL" "database_connection" "Database connection failed"
    sleep 1
    
    local total_count
    total_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "3" "${total_count}"
    
    # Verify each type is stored
    local etl_count
    etl_count=$(count_alerts "${TEST_COMPONENT}" "" "etl_scripts_found")
    local freshness_count
    freshness_count=$(count_alerts "${TEST_COMPONENT}" "" "data_warehouse_freshness")
    local connection_count
    connection_count=$(count_alerts "${TEST_COMPONENT}" "" "database_connection")
    
    assert_equal "1" "${etl_count}"
    assert_equal "1" "${freshness_count}"
    assert_equal "1" "${connection_count}"
}

@test "Alerts are filtered by alert level correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "CRITICAL" "database_connection" "Database connection failed"
    sleep 1
    send_alert "${TEST_COMPONENT}" "WARNING" "etl_duration" "Long-running ETL job"
    sleep 1
    send_alert "${TEST_COMPONENT}" "INFO" "unused_index_count" "Unused indexes found"
    sleep 1
    
    local critical_count
    critical_count=$(count_alerts "${TEST_COMPONENT}" "critical")
    local warning_count
    warning_count=$(count_alerts "${TEST_COMPONENT}" "warning")
    local info_count
    info_count=$(count_alerts "${TEST_COMPONENT}" "info")
    
    assert_equal "1" "${critical_count}"
    assert_equal "1" "${warning_count}"
    assert_equal "1" "${info_count}"
}

@test "Alert message contains threshold information" {
    skip_if_database_not_available
    
    local test_message="Data warehouse freshness exceeded: 7200s (threshold: 3600s)"
    send_alert "${TEST_COMPONENT}" "WARNING" "data_warehouse_freshness" "${test_message}"
    sleep 1
    
    local result
    result=$(get_latest_alert_message "${TEST_COMPONENT}")
    
    assert_equal "${test_message}" "${result}"
}

@test "Alert timestamp is set correctly" {
    skip_if_database_not_available
    
    local before_time
    before_time=$(date +%s)
    
    send_alert "${TEST_COMPONENT}" "WARNING" "timestamp_test" "Test timestamp"
    sleep 1
    
    local after_time
    after_time=$(date +%s)
    
    local query="SELECT EXTRACT(EPOCH FROM created_at)::bigint FROM alerts WHERE component = '${TEST_COMPONENT}' LIMIT 1;"
    local alert_time
    alert_time=$(run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]')
    
    # Alert time should be between before and after
    assert [ "${alert_time}" -ge "${before_time}" ]
    assert [ "${alert_time}" -le "${after_time}" ]
}

@test "Email alerts are skipped when disabled" {
    skip_if_database_not_available
    skip_if_command_not_found mutt
    
    export SEND_ALERT_EMAIL="false"
    
    # This should not fail even if mutt is not configured
    send_alert "${TEST_COMPONENT}" "WARNING" "email_test" "Test email alert"
    sleep 1
    
    # Alert should still be stored in database
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "1" "${alert_count}"
}

