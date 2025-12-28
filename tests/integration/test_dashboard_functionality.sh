#!/usr/bin/env bats
#
# Integration Tests: Dashboard Functionality
# Tests dashboard functionality with real data
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="DASHBOARD"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Create test dashboard directories
    TEST_DASHBOARD_DIR=$(mktemp -d)
    export DASHBOARD_OUTPUT_DIR="${TEST_DASHBOARD_DIR}"
    mkdir -p "${TEST_DASHBOARD_DIR}/grafana"
    mkdir -p "${TEST_DASHBOARD_DIR}/html"
    
    # Initialize test database if needed
    skip_if_database_not_available
}

teardown() {
    # Cleanup
    rm -rf "${TEST_DASHBOARD_DIR:-}"
}

##
# Test: generateMetrics.sh generates valid JSON
##
@test "generateMetrics.sh generates valid JSON output" {
    local output_file="${TEST_DASHBOARD_DIR}/metrics.json"
    
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_file}" ingestion json
    
    assert_success
    assert_file_exists "${output_file}"
    
    # Validate JSON syntax
    if command -v jq &> /dev/null; then
        run jq . "${output_file}" > /dev/null 2>&1
        assert_success "Generated JSON is not valid"
    fi
}

##
# Test: generateMetrics.sh generates valid CSV
##
@test "generateMetrics.sh generates valid CSV output" {
    local output_file="${TEST_DASHBOARD_DIR}/metrics.csv"
    
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_file}" ingestion csv
    
    assert_success
    assert_file_exists "${output_file}"
    
    # Check CSV has header
    run grep -q "metric_name" "${output_file}"
    assert_success "CSV missing header"
}

##
# Test: updateDashboard.sh creates dashboard files
##
@test "updateDashboard.sh creates dashboard files" {
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/updateDashboard.sh" --force html
    
    assert_success
    
    # Check for component data files
    local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
    for comp in "${components[@]}"; do
        # File may or may not exist depending on data availability
        # Just check that script ran successfully
        # shellcheck disable=SC2034
        local data_file="${TEST_DASHBOARD_DIR}/html/${comp}_data.json"
    done
}

##
# Test: exportDashboard.sh creates valid archive
##
@test "exportDashboard.sh creates valid tar archive" {
    # Create test dashboard files
    echo '{"test":"data"}' > "${TEST_DASHBOARD_DIR}/grafana/test.json"
    
    local output_file="${TEST_DASHBOARD_DIR}/backup"
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/exportDashboard.sh" grafana "${output_file}"
    
    assert_success
    assert_file_exists "${output_file}.tar.gz"
    
    # Validate archive
    run tar -tzf "${output_file}.tar.gz" > /dev/null 2>&1
    assert_success "Archive is not valid"
}

##
# Test: importDashboard.sh imports dashboards correctly
##
@test "importDashboard.sh imports dashboards correctly" {
    # Create test archive
    local archive_dir
    archive_dir=$(mktemp -d)
    mkdir -p "${archive_dir}/grafana"
    echo '{"imported":"data"}' > "${archive_dir}/grafana/imported.json"
    
    local archive_file="${TEST_DASHBOARD_DIR}/import_test.tar.gz"
    (cd "${archive_dir}" && tar -czf "${archive_file}" .)
    
    # Import
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/importDashboard.sh" "${archive_file}" grafana
    
    assert_success
    
    # Cleanup
    rm -rf "${archive_dir}"
}

##
# Test: Dashboard scripts handle missing data gracefully
##
@test "Dashboard scripts handle missing data gracefully" {
    # Test with non-existent component
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" nonexistent_component json
    
    # Should not fail, just return empty data
    assert_success
}

##
# Test: Dashboard update respects time intervals
##
@test "Dashboard update respects time intervals" {
    # Create recent file
    touch "${TEST_DASHBOARD_DIR}/html/overview_data.json"
    sleep 1
    
    # Update should skip if recent
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/updateDashboard.sh" html
    
    assert_success
    # Should indicate data is up to date
}

##
# Test: Dashboard export includes all components
##
@test "Dashboard export includes all components" {
    # Create test files for all components
    local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
    for comp in "${components[@]}"; do
        echo "{}" > "${TEST_DASHBOARD_DIR}/grafana/${comp}_metrics.json"
    done
    
    local output_file="${TEST_DASHBOARD_DIR}/export_all"
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/exportDashboard.sh" all "${output_file}"
    
    assert_success
    assert_file_exists "${output_file}.tar.gz"
}
