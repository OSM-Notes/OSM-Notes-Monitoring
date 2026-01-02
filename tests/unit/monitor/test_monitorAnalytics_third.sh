#!/usr/bin/env bash
#
# Third Unit Tests: monitorAnalytics.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    export ANALYTICS_ENABLED="true"
    export ANALYTICS_QUERY_PERFORMANCE_THRESHOLD="1000"
    export ANALYTICS_ERROR_RATE_THRESHOLD="5"
    export ANALYTICS_DATA_FRESHNESS_THRESHOLD="3600"
    
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
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorAnalytics.sh"
    
    init_logging "${TEST_LOG_DIR}/test_monitorAnalytics_third.log" "test_monitorAnalytics_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_query_performance handles very fast queries
##
@test "check_query_performance handles very fast queries" {
    # Mock execute_sql_query to return fast query times
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "10|20|30"  # All queries under threshold
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
    
    run check_query_performance
    assert_success
}

##
# Test: check_error_rate handles zero errors
##
@test "check_error_rate handles zero errors" {
    # Mock execute_sql_query to return zero errors
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "0|1000"  # errors=0, total=1000
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
# Test: check_data_freshness handles very fresh data
##
@test "check_data_freshness handles very fresh data" {
    # Mock execute_sql_query to return recent timestamp
    # shellcheck disable=SC2317
    function execute_sql_query() {
        date -u +%Y-%m-%d\ %H:%M:%S  # Current timestamp
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
    
    run check_data_freshness
    assert_success
}

##
# Test: main handles --check option with all checks
##
@test "main handles --check option with all checks" {
    # Mock check functions
    # shellcheck disable=SC2317
    function check_query_performance() {
        return 0
    }
    export -f check_query_performance
    
    # shellcheck disable=SC2317
    function check_error_rate() {
        return 0
    }
    export -f check_error_rate
    
    # shellcheck disable=SC2317
    function check_data_freshness() {
        return 0
    }
    export -f check_data_freshness
    
    run main --check
    assert_success
}

##
# Test: main handles verbose mode
##
@test "main handles verbose mode" {
    # Mock check functions
    # shellcheck disable=SC2317
    function check_query_performance() {
        return 0
    }
    export -f check_query_performance
    
    run main --verbose
    assert_success
}
