#!/usr/bin/env bats
#
# Third Unit Tests: generateMetrics.sh
# Third test file to reach 80% coverage
#

export TEST_COMPONENT="DASHBOARD"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_DIR}/test_generateMetrics_third.log" "test_generateMetrics_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: generate_metrics handles multiple components
##
@test "generate_metrics handles multiple components" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo '{"component":"ingestion","metric":"test","value":100}'
        return 0
    }
    export -f psql
    
    run generate_metrics "ingestion,analytics"
    assert_success
}

##
# Test: generate_metrics handles CSV format
##
@test "generate_metrics handles CSV format" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo 'metric,value'
        echo 'test,100'
        return 0
    }
    export -f psql
    
    run generate_metrics "ingestion" "csv"
    assert_success
}

##
# Test: main handles --format option
##
@test "main handles --format option" {
    # Mock generate_metrics
    # shellcheck disable=SC2317
    function generate_metrics() {
        return 0
    }
    export -f generate_metrics
    
    run main --format csv --component "ingestion"
    assert_success
}
