#!/usr/bin/env bats
#
# Third Unit Tests: importDashboard.sh
# Third test file to reach 80% coverage
#

export TEST_COMPONENT="DASHBOARD"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_DIR}/test_importDashboard_third.log" "test_importDashboard_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: import_dashboard handles overwrite existing
##
@test "import_dashboard handles overwrite existing" {
    local test_file="${TEST_LOG_DIR}/test_dashboard.json"
    echo '{"dashboard": {"title": "Test"}}' > "${test_file}"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    export -f psql
    
    run import_dashboard "${test_file}" "overwrite"
    assert_success
    
    rm -f "${test_file}"
}

##
# Test: import_dashboard handles skip existing
##
@test "import_dashboard handles skip existing" {
    local test_file="${TEST_LOG_DIR}/test_dashboard.json"
    echo '{"dashboard": {"title": "Test"}}' > "${test_file}"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    export -f psql
    
    run import_dashboard "${test_file}" "skip"
    assert_success
    
    rm -f "${test_file}"
}

##
# Test: main handles --overwrite option
##
@test "main handles --overwrite option" {
    local test_file="${TEST_LOG_DIR}/test_dashboard.json"
    echo '{"dashboard": {"title": "Test"}}' > "${test_file}"
    
    # Mock import_dashboard
    # shellcheck disable=SC2317
    function import_dashboard() {
        return 0
    }
    export -f import_dashboard
    
    run main --overwrite --file "${test_file}"
    assert_success
    
    rm -f "${test_file}"
}
