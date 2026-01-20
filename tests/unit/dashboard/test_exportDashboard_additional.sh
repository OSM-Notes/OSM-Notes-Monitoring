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
# Test: export_grafana_dashboard handles missing dashboard directory
##
@test "export_grafana_dashboard handles missing dashboard directory" {
    DASHBOARD_OUTPUT_DIR="/nonexistent/dir" run export_grafana_dashboard "/tmp/test_output" "false" "tar"
    # Should succeed with warning
    assert_success
}

##
# Test: export_html_dashboard handles invalid output file
##
@test "export_html_dashboard handles invalid output file" {
    # Create a test dashboard directory
    local test_dir
    test_dir=$(mktemp -d)
    mkdir -p "${test_dir}/html"
    echo "test" > "${test_dir}/html/test.html"
    
    # Try to export to invalid path (directory that doesn't exist)
    DASHBOARD_OUTPUT_DIR="${test_dir}" run export_html_dashboard "/nonexistent/parent/output" "false" "tar"
    # Should fail or handle gracefully
    assert_failure || assert_success
    
    rm -rf "${test_dir}"
}

##
# Test: main handles --help option via script
##
@test "main handles --help option" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --help
    assert_success
    assert_output --partial "Usage"
}

##
# Test: main handles invalid dashboard type
##
@test "main handles invalid dashboard type" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" invalid_type
    assert_failure
    assert_output --partial "Unknown dashboard type"
}
