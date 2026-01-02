#!/usr/bin/env bats
#
# Additional Unit Tests: exportDashboard.sh
# Additional tests for dashboard export to increase coverage
#

export TEST_COMPONENT="DASHBOARD"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_DIR}/test_exportDashboard_additional.log" "test_exportDashboard_additional"
    
    # Source the script
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: export_dashboard handles missing dashboard name
##
@test "export_dashboard handles missing dashboard name" {
    run export_dashboard ""
    assert_failure
}

##
# Test: export_dashboard handles invalid output file
##
@test "export_dashboard handles invalid output file" {
    run export_dashboard "test_dashboard" "/invalid/path/file.json"
    assert_failure
}

##
# Test: main handles --output option
##
@test "main handles --output option" {
    # Mock export_dashboard
    # shellcheck disable=SC2317
    function export_dashboard() {
        return 0
    }
    export -f export_dashboard
    
    run main --output "/tmp/test.json" "test_dashboard"
    assert_success
}

##
# Test: main handles --help option
##
@test "main handles --help option" {
    # Mock usage
    # shellcheck disable=SC2317
    function usage() {
        return 0
    }
    export -f usage
    
    run main --help
    assert_success
}
