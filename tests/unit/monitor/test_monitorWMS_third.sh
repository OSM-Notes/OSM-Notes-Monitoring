#!/usr/bin/env bash
#
# Third Unit Tests: monitorWMS.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    
    export WMS_ENABLED="true"
    export WMS_AVAILABILITY_THRESHOLD="95"
    export WMS_RESPONSE_TIME_THRESHOLD="1000"
    
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
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorWMS.sh"
    
    init_logging "${TEST_LOG_DIR}/test_monitorWMS_third.log" "test_monitorWMS_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_wms_availability handles 100% availability
##
@test "check_wms_availability handles 100% availability" {
    # Mock execute_sql_query to return 100% availability
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "100"  # 100% availability
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
    
    run check_wms_availability
    assert_success
}

##
# Test: check_wms_response_time handles very fast response
##
@test "check_wms_response_time handles very fast response" {
    # Mock get_http_response_time to return fast time
    # shellcheck disable=SC2317
    function get_http_response_time() {
        echo "50"  # 50ms response time
        return 0
    }
    export -f get_http_response_time
    
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
    
    run check_wms_response_time
    assert_success
}

##
# Test: main handles --check option
##
@test "main handles --check option" {
    # Mock check functions
    # shellcheck disable=SC2317
    function check_wms_availability() {
        return 0
    }
    export -f check_wms_availability
    
    # shellcheck disable=SC2317
    function check_wms_response_time() {
        return 0
    }
    export -f check_wms_response_time
    
    run main --check
    assert_success
}
