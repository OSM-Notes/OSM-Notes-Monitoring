#!/usr/bin/env bats
#
# Unit Tests: exportDashboard.sh
# Tests for dashboard export script
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="DASHBOARD"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_exportDashboard.log"
    init_logging "${LOG_FILE}" "test_exportDashboard"
    
    # Create test dashboard directories
    TEST_DASHBOARD_DIR=$(mktemp -d)
    export DASHBOARD_OUTPUT_DIR="${TEST_DASHBOARD_DIR}"
    mkdir -p "${TEST_DASHBOARD_DIR}/grafana"
    mkdir -p "${TEST_DASHBOARD_DIR}/html"
    
    # Create test files
    echo '{"test":"grafana"}' > "${TEST_DASHBOARD_DIR}/grafana/test.json"
    echo '<html>test</html>' > "${TEST_DASHBOARD_DIR}/html/test.html"
    
    # Create output directory
    TEST_OUTPUT_DIR=$(mktemp -d)
    export TEST_OUTPUT_DIR
}

teardown() {
    # Cleanup
    rm -rf "${TEST_DASHBOARD_DIR:-}"
    rm -rf "${TEST_OUTPUT_DIR:-}"
}

##
# Test: exportDashboard.sh usage
##
@test "exportDashboard.sh shows usage with --help" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --help
    assert_success
    assert [[ "${output}" =~ Usage: ]]
    assert [[ "${output}" =~ exportDashboard.sh ]]
}

##
# Test: exportDashboard.sh exports Grafana dashboards
##
@test "exportDashboard.sh exports Grafana dashboards to directory" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" grafana "${TEST_OUTPUT_DIR}"
    assert_success
    assert_file_exists "${TEST_OUTPUT_DIR}/grafana/test.json"
}

##
# Test: exportDashboard.sh exports HTML dashboards
##
@test "exportDashboard.sh exports HTML dashboards to directory" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" html "${TEST_OUTPUT_DIR}"
    assert_success
    assert_file_exists "${TEST_OUTPUT_DIR}/html/test.html"
}

##
# Test: exportDashboard.sh exports all dashboards
##
@test "exportDashboard.sh exports all dashboards" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" all "${TEST_OUTPUT_DIR}"
    assert_success
    assert_file_exists "${TEST_OUTPUT_DIR}/grafana/test.json"
    assert_file_exists "${TEST_OUTPUT_DIR}/html/test.html"
}

##
# Test: exportDashboard.sh creates tar archive
##
@test "exportDashboard.sh creates tar archive" {
    local output_file="${TEST_OUTPUT_DIR}/backup"
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" grafana "${output_file}"
    assert_success
    assert_file_exists "${output_file}.tar.gz"
}

##
# Test: exportDashboard.sh creates zip archive
##
@test "exportDashboard.sh creates zip archive with --format zip" {
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        skip "zip command not available"
    fi
    
    local output_file="${TEST_OUTPUT_DIR}/backup"
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --format zip grafana "${output_file}"
    assert_success
    assert_file_exists "${output_file}.zip"
}

##
# Test: exportDashboard.sh includes metrics data
##
@test "exportDashboard.sh includes metrics data with --include-data" {
    # Mock generateMetrics.sh
    function generateMetrics.sh() {
        echo '{"test":"metrics"}'
    }
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --include-data grafana "${TEST_OUTPUT_DIR}"
    assert_success
    # Should create metrics directory
    assert_dir_exists "${TEST_OUTPUT_DIR}/metrics" || assert_dir_exists "${TEST_OUTPUT_DIR}/grafana/metrics"
}

##
# Test: exportDashboard.sh handles missing dashboard directory
##
@test "exportDashboard.sh handles missing dashboard directory gracefully" {
    rm -rf "${TEST_DASHBOARD_DIR}/grafana"
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" grafana "${TEST_OUTPUT_DIR}"
    # Should handle gracefully
    assert_success
}
