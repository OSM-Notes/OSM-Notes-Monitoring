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
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR to avoid permission issues
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
    assert_output --partial "Usage:"
    assert_output --partial "exportDashboard.sh"
}

##
# Test: exportDashboard.sh exports Grafana dashboards
##
@test "exportDashboard.sh exports Grafana dashboards to directory" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" grafana "${TEST_OUTPUT_DIR}"
    assert_success
    assert_file_exists "${TEST_OUTPUT_DIR}/grafana/test.json"
}

##
# Test: exportDashboard.sh exports HTML dashboards
##
@test "exportDashboard.sh exports HTML dashboards to directory" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" html "${TEST_OUTPUT_DIR}"
    assert_success
    assert_file_exists "${TEST_OUTPUT_DIR}/html/test.html"
}

##
# Test: exportDashboard.sh exports all dashboards
##
@test "exportDashboard.sh exports all dashboards" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" all "${TEST_OUTPUT_DIR}"
    assert_success
    assert_file_exists "${TEST_OUTPUT_DIR}/grafana/test.json"
    assert_file_exists "${TEST_OUTPUT_DIR}/html/test.html"
}

##
# Test: exportDashboard.sh creates tar archive
##
@test "exportDashboard.sh creates tar archive" {
    local output_file="${TEST_OUTPUT_DIR}/backup"
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" grafana "${output_file}"
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
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" --format zip grafana "${output_file}"
    assert_success
    assert_file_exists "${output_file}.zip"
}

##
# Test: exportDashboard.sh includes metrics data
##
@test "exportDashboard.sh includes metrics data with --include-data" {
    # Mock generateMetrics.sh script
    local metrics_script="${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh"
    local mock_script="${TEST_OUTPUT_DIR}/mock_generateMetrics.sh"

    # Create mock script that outputs JSON without database calls
    cat > "${mock_script}" << 'EOF'
#!/usr/bin/env bash
echo '{"test":"metrics"}'
EOF
    chmod +x "${mock_script}"

    # Temporarily replace generateMetrics.sh with mock
    local original_script="${metrics_script}.orig"
    if [[ -f "${metrics_script}" ]]; then
        mv "${metrics_script}" "${original_script}"
    fi
    cp "${mock_script}" "${metrics_script}"

    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" --include-data grafana "${TEST_OUTPUT_DIR}"

    # Restore original script
    if [[ -f "${original_script}" ]]; then
        mv "${original_script}" "${metrics_script}"
    fi

    assert_success
    # Should create metrics directory
    assert_dir_exists "${TEST_OUTPUT_DIR}/metrics" || assert_dir_exists "${TEST_OUTPUT_DIR}/grafana/metrics"
}

##
# Test: exportDashboard.sh handles missing dashboard directory
##
@test "exportDashboard.sh handles missing dashboard directory gracefully" {
    rm -rf "${TEST_DASHBOARD_DIR}/grafana"
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" grafana "${TEST_OUTPUT_DIR}"
    # Should handle gracefully
    assert_success
}

@test "exportDashboard.sh handles --verbose flag" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" --verbose grafana "${TEST_OUTPUT_DIR}"
    assert_success
}

@test "exportDashboard.sh handles --quiet flag" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" --quiet grafana "${TEST_OUTPUT_DIR}"
    assert_success
}

@test "exportDashboard.sh handles --config flag" {
    local test_config="${BATS_TEST_DIRNAME}/../../../tmp/test_exportDashboard_config.conf"
    mkdir -p "$(dirname "${test_config}")"
    echo "TEST_CONFIG_VAR=test_value" > "${test_config}"

    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" --config "${test_config}" grafana "${TEST_OUTPUT_DIR}"
    assert_success

    rm -f "${test_config}"
}

@test "exportDashboard.sh handles --dashboard flag" {
    local custom_dir
    custom_dir=$(mktemp -d)
    mkdir -p "${custom_dir}/grafana"
    echo '{"custom":"dashboard"}' > "${custom_dir}/grafana/custom.json"

    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${custom_dir}" grafana "${TEST_OUTPUT_DIR}"
    assert_success

    rm -rf "${custom_dir}"
}

@test "exportDashboard.sh exports single JSON file" {
    local output_file="${TEST_OUTPUT_DIR}/single.json"
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" grafana "${output_file}"
    assert_success
    # Should create archive or file
    assert_file_exists "${output_file}.tar.gz" || assert_file_exists "${output_file}"
}

@test "exportDashboard.sh handles export format tar" {
    local output_file="${TEST_OUTPUT_DIR}/backup_tar"
    export EXPORT_FORMAT="tar"
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" grafana "${output_file}"
    assert_success
    assert_file_exists "${output_file}.tar.gz"
}

@test "exportDashboard.sh handles invalid dashboard type" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" invalid "${TEST_OUTPUT_DIR}"
    assert_failure
    # Check for error message about unknown or invalid dashboard type (check both stdout and stderr)
    assert_output --partial "Unknown" || assert_output --partial "invalid" || assert_output --partial "ERROR"
}

@test "exportDashboard.sh handles empty output directory" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" grafana ""
    # Should use default directory
    assert_success
}

@test "exportDashboard.sh includes data when --include-data is used" {
    # Mock generateMetrics.sh script
    local metrics_script="${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh"
    local mock_script="${TEST_OUTPUT_DIR}/mock_generateMetrics.sh"

    # Create mock script that outputs JSON without database calls
    cat > "${mock_script}" << 'EOF'
#!/usr/bin/env bash
echo '{"test":"metrics"}'
EOF
    chmod +x "${mock_script}"

    # Temporarily replace generateMetrics.sh with mock
    local original_script="${metrics_script}.orig"
    if [[ -f "${metrics_script}" ]]; then
        mv "${metrics_script}" "${original_script}"
    fi
    cp "${mock_script}" "${metrics_script}"

    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/exportDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" --include-data grafana "${TEST_OUTPUT_DIR}"

    # Restore original script
    if [[ -f "${original_script}" ]]; then
        mv "${original_script}" "${metrics_script}"
    fi

    assert_success
    # Should create metrics directory
    assert_dir_exists "${TEST_OUTPUT_DIR}/metrics" || assert_dir_exists "${TEST_OUTPUT_DIR}/grafana/metrics"
}
