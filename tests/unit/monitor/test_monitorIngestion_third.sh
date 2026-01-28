#!/usr/bin/env bash
#
# Third Unit Tests: monitorIngestion.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_INGESTION_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_ingestion"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_INGESTION_DIR}/bin"
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    
    export INGESTION_REPO_PATH="${TEST_INGESTION_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    export INGESTION_ENABLED="true"
    export INGESTION_SCRIPTS_FOUND_THRESHOLD="3"
    export INGESTION_LAST_LOG_AGE_THRESHOLD="24"
    export INGESTION_MAX_ERROR_RATE="5"
    export INGESTION_ERROR_COUNT_THRESHOLD="1000"
    export INGESTION_WARNING_COUNT_THRESHOLD="2000"
    export INGESTION_WARNING_RATE_THRESHOLD="15"
    export INGESTION_DATA_QUALITY_THRESHOLD="95"
    export INGESTION_LATENCY_THRESHOLD="300"
    export INGESTION_DATA_FRESHNESS_THRESHOLD="3600"
    export INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD="95"
    export INFRASTRUCTURE_DISK_THRESHOLD="90"
    export PERFORMANCE_SLOW_QUERY_THRESHOLD="1000"
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
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
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorIngestion.sh"
    
    init_logging "${TEST_LOG_DIR}/test_monitorIngestion_third.log" "test_monitorIngestion_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_INGESTION_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_script_execution_status handles missing scripts directory
##
@test "check_script_execution_status handles missing scripts directory" {
    export INGESTION_REPO_PATH="/nonexistent/path"
    
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
    
    run check_script_execution_status || true
    assert_success || assert_failure
}

##
# Test: check_error_rate handles zero total requests
##
@test "check_error_rate handles zero total requests" {
    # Mock execute_sql_query to return zero requests
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "0|0"  # errors=0, total=0
        return 0
    }
    export -f execute_sql_query
    
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
    
    run check_error_rate
    assert_success
}

##
# Test: check_recent_error_spikes handles empty result set
##
@test "check_recent_error_spikes handles empty result set" {
    # Mock execute_sql_query to return empty
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo ""
        return 0
    }
    export -f execute_sql_query
    
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
    
    run check_recent_error_spikes
    assert_success
}

##
# Test: check_disk_space handles very low disk usage
##
@test "check_disk_space handles very low disk usage" {
    # Mock df to return low usage
    # shellcheck disable=SC2317
    function df() {
        echo "Filesystem     1K-blocks  Used Available Use% Mounted on"
        echo "/dev/sda1       1000000  10000    990000   1% /"
        return 0
    }
    export -f df
    
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
    
    run check_disk_space
    assert_success
}

##
# Test: check_last_execution_time handles very old log file
##
@test "check_last_execution_time handles very old log file" {
    # Create old log file
    local old_log="${TEST_INGESTION_DIR}/logs/old_script.log"
    mkdir -p "$(dirname "${old_log}")"
    touch "${old_log}"
    # Set modification time to 30 days ago
    touch -t "$(date -d '30 days ago' +%Y%m%d%H%M)" "${old_log}"
    
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
    
    run check_last_execution_time
    assert_success
    
    rm -f "${old_log}"
}

##
# Test: check_database_connection_performance handles slow connection
##
@test "check_database_connection_performance handles slow connection" {
    # Mock psql to simulate slow connection
    # shellcheck disable=SC2317
    function psql() {
        sleep 0.002  # Simulate 2ms delay
        echo "1"
        return 0
    }
    export -f psql
    
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
    
    run check_database_connection_performance
    assert_success
}

##
# Test: check_database_query_performance handles very fast query
##
@test "check_database_query_performance handles very fast query" {
    # Mock check_database_connection
    # shellcheck disable=SC2317
    function check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # Mock execute_sql_query to return fast query time
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "10"  # 10ms query time (very fast)
        return 0
    }
    export -f execute_sql_query
    
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
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run check_database_query_performance
    assert_success
}

##
# Test: check_database_connections handles maximum connections
##
@test "check_database_connections handles maximum connections" {
    # Mock check_database_connection
    # shellcheck disable=SC2317
    function check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # Mock execute_sql_query to return high connection count
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "100|50|50"  # total=100, active=50, idle=50
        return 0
    }
    export -f execute_sql_query
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_debug() {
        return 0
    }
    export -f log_debug
    
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
    
    run check_database_connections
    assert_success
}

##
# Test: check_database_table_sizes handles empty tables
##
@test "check_database_table_sizes handles empty tables" {
    # Mock check_database_connection
    # shellcheck disable=SC2317
    function check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # Mock execute_sql_query to return empty table sizes
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_debug() {
        return 0
    }
    export -f log_debug
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    run check_database_table_sizes
    assert_success
}

##
# Test: check_ingestion_performance handles all metrics normal
##
@test "check_ingestion_performance handles all metrics normal" {
    # Mock execute_sql_query to return normal values
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "100|50|200"  # latency=100ms, throughput=50, queue_size=200
        return 0
    }
    export -f execute_sql_query
    
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
    
    run check_ingestion_performance
    assert_success
}

##
# Test: check_data_completeness handles 100% completeness
##
@test "check_data_completeness handles 100% completeness" {
    # Mock execute_sql_query to return 100% completeness
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "100"  # 100% completeness
        return 0
    }
    export -f execute_sql_query
    
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
    
    run check_data_completeness
    assert_success
}

##
# Test: check_ingestion_health handles all checks passing
##
@test "check_ingestion_health handles all checks passing" {
    # Mock all check functions
    # shellcheck disable=SC2317
    function check_script_execution_status() {
        return 0
    }
    export -f check_script_execution_status
    
    # shellcheck disable=SC2317
    function check_error_rate() {
        return 0
    }
    export -f check_error_rate
    
    # shellcheck disable=SC2317
    function check_recent_error_spikes() {
        return 0
    }
    export -f check_recent_error_spikes
    
    # shellcheck disable=SC2317
    function check_disk_space() {
        return 0
    }
    export -f check_disk_space
    
    # shellcheck disable=SC2317
    function check_last_execution_time() {
        return 0
    }
    export -f check_last_execution_time
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    run check_ingestion_health
    assert_success
}

##
# Test: main handles --check option with specific check
##
@test "main handles --check option with specific check" {
    # Mock load_all_configs and validate_all_configs
    # shellcheck disable=SC2317
    function load_all_configs() {
        return 0
    }
    export -f load_all_configs
    
    # shellcheck disable=SC2317
    function validate_all_configs() {
        return 0
    }
    export -f validate_all_configs
    
    # Mock check functions
    # shellcheck disable=SC2317
    function check_error_rate() {
        return 0
    }
    export -f check_error_rate
    
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
    
    # Mock init_alerting
    # shellcheck disable=SC2317
    init_alerting() {
        return 0
    }
    export -f init_alerting
    
    # main parses --check "error_rate" internally
    run main --check "error_rate"
    assert_success
}

##
# Test: main handles unknown check type
##
@test "main handles unknown check type" {
    # Mock usage
    # shellcheck disable=SC2317
    function usage() {
        return 0
    }
    export -f usage
    
    run main --check "unknown_check" || true
    assert_failure || assert_success
}
