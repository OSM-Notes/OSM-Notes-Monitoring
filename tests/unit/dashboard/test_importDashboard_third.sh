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
    
    # Set DASHBOARD_OUTPUT_DIR
    # shellcheck disable=SC2030,SC2031
    # SC2030/SC2031: Variable modification in subshell is expected in BATS tests
    export DASHBOARD_OUTPUT_DIR="${TEST_LOG_DIR}/dashboards"
    mkdir -p "${DASHBOARD_OUTPUT_DIR}/grafana"
    
    run import_grafana_dashboard "${test_file}" "true"
    assert_success
    
    rm -f "${test_file}"
    rm -rf "${DASHBOARD_OUTPUT_DIR}"
}

##
# Test: import_dashboard handles skip existing
##
@test "import_dashboard handles skip existing" {
    local test_file="${TEST_LOG_DIR}/test_dashboard.json"
    echo '{"dashboard": {"title": "Test"}}' > "${test_file}"
    
    # Set DASHBOARD_OUTPUT_DIR
    # shellcheck disable=SC2030,SC2031
    # SC2030/SC2031: Variable modification in subshell is expected in BATS tests
    export DASHBOARD_OUTPUT_DIR="${TEST_LOG_DIR}/dashboards"
    mkdir -p "${DASHBOARD_OUTPUT_DIR}/grafana"
    
    run import_grafana_dashboard "${test_file}" "false"
    assert_success
    
    rm -f "${test_file}"
    rm -rf "${DASHBOARD_OUTPUT_DIR}"
}

##
# Test: main handles --overwrite option
##
@test "main handles --overwrite option" {
    local test_file="${TEST_LOG_DIR}/test_dashboard.json"
    echo '{"dashboard": {"title": "Test"}}' > "${test_file}"
    
    # Set DASHBOARD_OUTPUT_DIR
    # shellcheck disable=SC2030,SC2031
    # SC2030/SC2031: Variable modification in subshell is expected in BATS tests
    export DASHBOARD_OUTPUT_DIR="${TEST_LOG_DIR}/dashboards"
    mkdir -p "${DASHBOARD_OUTPUT_DIR}/grafana"
    
    run bash "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --overwrite "${test_file}" grafana
    assert_success
    
    rm -f "${test_file}"
    rm -rf "${DASHBOARD_OUTPUT_DIR}"
}
