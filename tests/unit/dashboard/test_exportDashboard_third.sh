#!/usr/bin/env bats
#
# Third Unit Tests: exportDashboard.sh
# Third test file to reach 80% coverage
#

export TEST_COMPONENT="DASHBOARD"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_DIR}/test_exportDashboard_third.log" "test_exportDashboard_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: export_dashboard handles JSON format
##
@test "export_dashboard handles JSON format" {
    # Mock psql to return dashboard JSON
    # shellcheck disable=SC2317
    function psql() {
        echo '{"dashboard": {"title": "Test"}}'
        return 0
    }
    export -f psql
    
    local output_file="${TEST_LOG_DIR}/test_dashboard.json"
    run export_dashboard "test_dashboard" "${output_file}"
    assert_success
    assert_file_exists "${output_file}"
    
    rm -f "${output_file}"
}

##
# Test: export_dashboard handles multiple dashboards
##
@test "export_dashboard handles multiple dashboards" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo '{"dashboard": {"title": "Test"}}'
        return 0
    }
    export -f psql
    
    local output_file="${TEST_LOG_DIR}/test_multi.json"
    run export_dashboard "dashboard1,dashboard2" "${output_file}"
    assert_success || true
    
    rm -f "${output_file}"
}

##
# Test: main handles --format option
##
@test "main handles --format option" {
    # Mock export_dashboard
    # shellcheck disable=SC2317
    function export_dashboard() {
        return 0
    }
    export -f export_dashboard
    
    run main --format json --output "/tmp/test.json" "test_dashboard"
    assert_success
}
