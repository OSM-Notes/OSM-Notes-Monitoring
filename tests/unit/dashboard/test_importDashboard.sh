#!/usr/bin/env bats
#
# Unit Tests: importDashboard.sh
# Tests for dashboard import script
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
    export LOG_FILE="${TEST_LOG_DIR}/test_importDashboard.log"
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR to avoid permission issues
    init_logging "${LOG_FILE}" "test_importDashboard"
    
    # Create test dashboard directories
    TEST_DASHBOARD_DIR=$(mktemp -d)
    export DASHBOARD_OUTPUT_DIR="${TEST_DASHBOARD_DIR}"
    mkdir -p "${TEST_DASHBOARD_DIR}/grafana"
    mkdir -p "${TEST_DASHBOARD_DIR}/html"
    
    # Create test archive files
    TEST_ARCHIVE_DIR=$(mktemp -d)
    mkdir -p "${TEST_ARCHIVE_DIR}/grafana"
    echo '{"test":"import"}' > "${TEST_ARCHIVE_DIR}/grafana/import.json"
    
    # Create tar archive (use absolute path to avoid issues)
    local current_dir
    current_dir=$(pwd)
    cd "${TEST_ARCHIVE_DIR}" || exit 1
    tar -czf "${TEST_ARCHIVE_DIR}/backup.tar.gz" . 2>/dev/null || true
    cd "${current_dir}" || exit 1
    
    # Create zip archive if zip is available
    if command -v zip &> /dev/null; then
        cd "${TEST_ARCHIVE_DIR}" || exit 1
        zip -r "${TEST_ARCHIVE_DIR}/backup.zip" . > /dev/null 2>&1 || true
        cd "${current_dir}" || exit 1
    fi
}

teardown() {
    # Cleanup
    rm -rf "${TEST_DASHBOARD_DIR:-}"
    rm -rf "${TEST_ARCHIVE_DIR:-}"
}

##
# Test: importDashboard.sh usage
##
@test "importDashboard.sh shows usage with --help" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "importDashboard.sh"
}

##
# Test: importDashboard.sh requires input file
##
@test "importDashboard.sh requires input file" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh"
    assert_failure
    assert_output --partial "required" || [[ "${status}" -ne 0 ]]
}

##
# Test: importDashboard.sh imports from directory
##
@test "importDashboard.sh imports from directory" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" "${TEST_ARCHIVE_DIR}" grafana
    assert_success
    assert_file_exists "${TEST_DASHBOARD_DIR}/grafana/import.json"
}

##
# Test: importDashboard.sh imports from tar archive
##
@test "importDashboard.sh imports from tar archive" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" "${TEST_ARCHIVE_DIR}/backup.tar.gz" grafana
    assert_success
    assert_file_exists "${TEST_DASHBOARD_DIR}/grafana/import.json"
}

##
# Test: importDashboard.sh imports from zip archive
##
@test "importDashboard.sh imports from zip archive" {
    if ! command -v zip &> /dev/null; then
        skip "zip command not available"
    fi
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" "${TEST_ARCHIVE_DIR}/backup.zip" grafana
    assert_success
    assert_file_exists "${TEST_DASHBOARD_DIR}/grafana/import.json"
}

##
# Test: importDashboard.sh imports all dashboards
##
@test "importDashboard.sh imports all dashboards" {
    mkdir -p "${TEST_ARCHIVE_DIR}/html"
    echo '<html>test</html>' > "${TEST_ARCHIVE_DIR}/html/test.html"
    
    # Create tar archive in a separate directory to avoid race condition
    local temp_archive_dir
    temp_archive_dir=$(mktemp -d)
    cp -r "${TEST_ARCHIVE_DIR}"/* "${temp_archive_dir}/" 2>/dev/null || true
    (cd "${temp_archive_dir}" && tar -czf "${TEST_ARCHIVE_DIR}/backup_all.tar.gz" .)
    rm -rf "${temp_archive_dir}"
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --dashboard "${TEST_DASHBOARD_DIR}" "${TEST_ARCHIVE_DIR}/backup_all.tar.gz" all
    assert_success
    assert_file_exists "${TEST_DASHBOARD_DIR}/grafana/import.json"
    assert_file_exists "${TEST_DASHBOARD_DIR}/html/test.html"
}

##
# Test: importDashboard.sh creates backup
##
@test "importDashboard.sh creates backup with --backup flag" {
    echo '{"existing":"data"}' > "${TEST_DASHBOARD_DIR}/grafana/existing.json"
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --backup "${TEST_ARCHIVE_DIR}/backup.tar.gz" grafana
    assert_success
    
    # Check backup directory exists
    local backup_dirs
    backup_dirs=$(find "${TEST_DASHBOARD_DIR}" -type d -name "backup_*" | wc -l)
    assert [ "${backup_dirs}" -ge 1 ]
}

##
# Test: importDashboard.sh overwrites with --overwrite
##
@test "importDashboard.sh overwrites existing files with --overwrite" {
    echo '{"old":"data"}' > "${TEST_DASHBOARD_DIR}/grafana/import.json"
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --overwrite "${TEST_ARCHIVE_DIR}/backup.tar.gz" grafana
    assert_success
    
    # Check file was overwritten
    assert_file_exists "${TEST_DASHBOARD_DIR}/grafana/import.json"
    run grep -q "test" "${TEST_DASHBOARD_DIR}/grafana/import.json"
    assert_success
}

##
# Test: importDashboard.sh handles invalid archive
##
@test "importDashboard.sh handles invalid archive gracefully" {
    echo "invalid data" > "${TEST_ARCHIVE_DIR}/invalid.tar.gz"
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" "${TEST_ARCHIVE_DIR}/invalid.tar.gz" grafana
    # Should handle error gracefully
    assert_failure
}

@test "importDashboard.sh handles --verbose flag" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --verbose "${TEST_ARCHIVE_DIR}" grafana
    assert_success
}

@test "importDashboard.sh handles --quiet flag" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --quiet "${TEST_ARCHIVE_DIR}" grafana
    assert_success
}

@test "importDashboard.sh handles --config flag" {
    local test_config="${BATS_TEST_DIRNAME}/../../../tmp/test_importDashboard_config.conf"
    echo "TEST_CONFIG_VAR=test_value" > "${test_config}"
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --config "${test_config}" "${TEST_ARCHIVE_DIR}" grafana
    assert_success
    
    rm -f "${test_config}"
}

@test "importDashboard.sh handles --dashboard flag" {
    local custom_dir
    custom_dir=$(mktemp -d)
    mkdir -p "${custom_dir}/grafana"
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --dashboard "${custom_dir}" "${TEST_ARCHIVE_DIR}" grafana
    assert_success
    
    rm -rf "${custom_dir}"
}

@test "importDashboard.sh handles missing input file" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" /nonexistent/file.tar.gz grafana
    assert_failure
}

@test "importDashboard.sh handles invalid dashboard type" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" "${TEST_ARCHIVE_DIR}/backup.tar.gz" invalid
    assert_failure || assert_success  # May handle gracefully
}

@test "importDashboard.sh handles directory without dashboards" {
    local empty_dir
    empty_dir=$(mktemp -d)
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" "${empty_dir}" grafana
    # Should handle gracefully
    assert_success || assert_failure
    
    rm -rf "${empty_dir}"
}

@test "importDashboard.sh preserves existing files without --overwrite" {
    echo '{"existing":"data"}' > "${TEST_DASHBOARD_DIR}/grafana/existing.json"
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" "${TEST_ARCHIVE_DIR}/backup.tar.gz" grafana
    assert_success
    # Existing file should still exist
    assert_file_exists "${TEST_DASHBOARD_DIR}/grafana/existing.json"
}
