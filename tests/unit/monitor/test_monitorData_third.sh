#!/usr/bin/env bash
#
# Third Unit Tests: monitorData.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    
    export DATA_ENABLED="true"
    export DATA_QUALITY_THRESHOLD="95"
    export DATA_FRESHNESS_THRESHOLD="3600"
    
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
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorData.sh"
    
    init_logging "${TEST_LOG_DIR}/test_monitorData_third.log" "test_monitorData_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_data_quality handles 100% quality
##
@test "check_data_quality handles 100% quality" {
    # Mock execute_sql_query to return 100% quality
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "100"  # 100% quality
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
    
    run check_data_quality
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
# Test: main handles --check option
##
@test "main handles --check option" {
    # Mock check functions
    # shellcheck disable=SC2317
    function check_data_quality() {
        return 0
    }
    export -f check_data_quality
    
    # shellcheck disable=SC2317
    function check_data_freshness() {
        return 0
    }
    export -f check_data_freshness
    
    run main --check
    assert_success
}
