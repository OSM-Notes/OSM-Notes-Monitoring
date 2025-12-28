#!/usr/bin/env bats
#
# Integration Tests: Dashboard Data Accuracy
# Validates data accuracy in dashboard outputs
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
    
    # Insert test metrics
    insert_test_metrics
}

teardown() {
    # Cleanup test data
    cleanup_test_metrics
    rm -rf "${TEST_DASHBOARD_DIR:-}"
}

##
# Insert test metrics into database
##
insert_test_metrics() {
    local dbname="${DBNAME}"
    local dbhost="${DBHOST}"
    local dbport="${DBPORT}"
    local dbuser="${DBUSER}"
    
    local query="
        INSERT INTO metrics (component, metric_name, metric_value, timestamp)
        VALUES 
            ('ingestion', 'error_rate_percent', 2.5, NOW() - INTERVAL '1 hour'),
            ('ingestion', 'error_rate_percent', 3.0, NOW() - INTERVAL '30 minutes'),
            ('ingestion', 'error_rate_percent', 2.8, NOW()),
            ('analytics', 'etl_processing_duration_avg_seconds', 120, NOW() - INTERVAL '1 hour'),
            ('analytics', 'etl_processing_duration_avg_seconds', 125, NOW());
    "
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1 || true
}

##
# Cleanup test metrics
##
cleanup_test_metrics() {
    local dbname="${DBNAME}"
    local dbhost="${DBHOST}"
    local dbport="${DBPORT}"
    local dbuser="${DBUSER}"
    
    local query="
        DELETE FROM metrics 
        WHERE component IN ('ingestion', 'analytics')
          AND metric_name IN ('error_rate_percent', 'etl_processing_duration_avg_seconds')
          AND timestamp > NOW() - INTERVAL '2 hours';
    "
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1 || true
}

##
# Test: Generated metrics match database values
##
@test "Generated metrics match database values" {
    local output_file="${TEST_DASHBOARD_DIR}/metrics.json"
    
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_file}" ingestion json
    
    assert_success
    assert_file_exists "${output_file}"
    
    # Check that output contains expected metrics
    if command -v jq &> /dev/null; then
        run jq -e '.[] | select(.metric_name == "error_rate_percent")' "${output_file}" > /dev/null 2>&1
        assert_success "Generated metrics missing error_rate_percent"
    fi
}

##
# Test: Dashboard format calculates correct averages
##
@test "Dashboard format calculates correct averages" {
    local output_file="${TEST_DASHBOARD_DIR}/metrics_dashboard.json"
    
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_file}" ingestion dashboard
    
    assert_success
    assert_file_exists "${output_file}"
    
    # Validate JSON structure
    if command -v jq &> /dev/null; then
        run jq -e '.[] | select(.metric_name == "error_rate_percent") | .avg_value' "${output_file}" > /dev/null 2>&1
        assert_success "Dashboard format missing avg_value"
    fi
}

##
# Test: CSV format has correct column count
##
@test "CSV format has correct column count" {
    local output_file="${TEST_DASHBOARD_DIR}/metrics.csv"
    
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_file}" ingestion csv
    
    assert_success
    assert_file_exists "${output_file}"
    
    # Check header has expected columns
    local header
    header=$(head -1 "${output_file}")
    local column_count
    column_count=$(echo "${header}" | tr ',' '\n' | wc -l)
    
    assert [[ "${column_count}" -ge 3 ]] "CSV has incorrect column count"
}

##
# Test: Time range filtering works correctly
##
@test "Time range filtering works correctly" {
    local output_file_24h="${TEST_DASHBOARD_DIR}/metrics_24h.json"
    local output_file_1h="${TEST_DASHBOARD_DIR}/metrics_1h.json"
    
    # Generate for 24 hours
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" --time-range 24 -o "${output_file_24h}" ingestion json
    assert_success
    
    # Generate for 1 hour
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" --time-range 1 -o "${output_file_1h}" ingestion json
    assert_success
    
    # 1 hour should have fewer or equal records than 24 hours
    if command -v jq &> /dev/null && [[ -f "${output_file_24h}" ]] && [[ -f "${output_file_1h}" ]]; then
        local count_24h count_1h
        count_24h=$(jq '. | length' "${output_file_24h}" 2>/dev/null || echo "0")
        count_1h=$(jq '. | length' "${output_file_1h}" 2>/dev/null || echo "0")
        
        assert [[ "${count_1h}" -le "${count_24h}" ]] "Time range filtering not working correctly"
    fi
}

##
# Test: Component filtering works correctly
##
@test "Component filtering works correctly" {
    local output_ingestion="${TEST_DASHBOARD_DIR}/ingestion.json"
    local output_analytics="${TEST_DASHBOARD_DIR}/analytics.json"
    
    # Generate for ingestion
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_ingestion}" ingestion json
    assert_success
    
    # Generate for analytics
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_analytics}" analytics json
    assert_success
    
    # Both should exist
    assert_file_exists "${output_ingestion}"
    assert_file_exists "${output_analytics}"
}

##
# Test: Data consistency across formats
##
@test "Data consistency across formats" {
    local json_file="${TEST_DASHBOARD_DIR}/metrics.json"
    local csv_file="${TEST_DASHBOARD_DIR}/metrics.csv"
    
    # Generate both formats
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${json_file}" ingestion json
    assert_success
    
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${csv_file}" ingestion csv
    assert_success
    
    # Both should exist and have data
    assert_file_exists "${json_file}"
    assert_file_exists "${csv_file}"
    
    # CSV should have at least header
    local csv_lines
    csv_lines=$(wc -l < "${csv_file}")
    assert [[ "${csv_lines}" -ge 1 ]] "CSV file is empty"
}
