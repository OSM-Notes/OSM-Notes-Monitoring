#!/usr/bin/env bats
#
# Additional Unit Tests: importDashboard.sh
# Additional tests for dashboard import to increase coverage
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
    init_logging "${LOG_DIR}/test_importDashboard_additional.log" "test_importDashboard_additional"
    
    # Source the script
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: import_dashboard handles missing file
##
@test "import_dashboard handles missing file" {
    run import_dashboard "/nonexistent/file.json"
    assert_failure
}

##
# Test: import_dashboard handles invalid JSON
##
@test "import_dashboard handles invalid JSON" {
    local test_file="${TEST_LOG_DIR}/invalid.json"
    echo "invalid json content" > "${test_file}"
    
    run import_dashboard "${test_file}"
    assert_failure
    
    rm -f "${test_file}"
}

##
# Test: main handles --file option
##
@test "main handles --file option" {
    local test_file="${TEST_LOG_DIR}/test_dashboard.json"
    echo '{"dashboard": {"title": "Test"}}' > "${test_file}"
    
    # Mock import_dashboard
    # shellcheck disable=SC2317
    function import_dashboard() {
        return 0
    }
    export -f import_dashboard
    
    run main --file "${test_file}"
    assert_success
    
    rm -f "${test_file}"
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
