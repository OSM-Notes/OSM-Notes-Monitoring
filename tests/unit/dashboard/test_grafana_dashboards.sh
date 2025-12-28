#!/usr/bin/env bats
#
# Unit Tests: Grafana Dashboards
# Tests for Grafana dashboard JSON files
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

setup() {
    # Set test directory
    TEST_DASHBOARD_DIR="${BATS_TEST_DIRNAME}/../../../dashboards/grafana"
}

##
# Test: overview.json exists and is valid JSON
##
@test "overview.json exists and is valid JSON" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/overview.json"
    
    # Validate JSON syntax
    run jq . "${TEST_DASHBOARD_DIR}/overview.json" > /dev/null 2>&1
    assert_success "overview.json is not valid JSON"
}

##
# Test: overview.json has required dashboard structure
##
@test "overview.json has required dashboard structure" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/overview.json"
    
    # Check for dashboard object
    run jq -e '.dashboard' "${TEST_DASHBOARD_DIR}/overview.json" > /dev/null 2>&1
    assert_success "overview.json missing dashboard object"
    
    # Check for required fields
    run jq -e '.dashboard.title' "${TEST_DASHBOARD_DIR}/overview.json" > /dev/null 2>&1
    assert_success "overview.json missing title"
    
    run jq -e '.dashboard.panels' "${TEST_DASHBOARD_DIR}/overview.json" > /dev/null 2>&1
    assert_success "overview.json missing panels"
}

##
# Test: ingestion.json exists and is valid JSON
##
@test "ingestion.json exists and is valid JSON" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/ingestion.json"
    
    # Validate JSON syntax
    run jq . "${TEST_DASHBOARD_DIR}/ingestion.json" > /dev/null 2>&1
    assert_success "ingestion.json is not valid JSON"
}

##
# Test: ingestion.json has required structure
##
@test "ingestion.json has required dashboard structure" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/ingestion.json"
    
    # Check for dashboard object
    run jq -e '.dashboard' "${TEST_DASHBOARD_DIR}/ingestion.json" > /dev/null 2>&1
    assert_success "ingestion.json missing dashboard object"
    
    # Check for title
    run jq -e '.dashboard.title' "${TEST_DASHBOARD_DIR}/ingestion.json" > /dev/null 2>&1
    assert_success "ingestion.json missing title"
}

##
# Test: analytics.json exists and is valid JSON
##
@test "analytics.json exists and is valid JSON" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/analytics.json"
    
    # Validate JSON syntax
    run jq . "${TEST_DASHBOARD_DIR}/analytics.json" > /dev/null 2>&1
    assert_success "analytics.json is not valid JSON"
}

##
# Test: wms.json exists and is valid JSON
##
@test "wms.json exists and is valid JSON" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/wms.json"
    
    # Validate JSON syntax
    run jq . "${TEST_DASHBOARD_DIR}/wms.json" > /dev/null 2>&1
    assert_success "wms.json is not valid JSON"
}

##
# Test: api.json exists and is valid JSON
##
@test "api.json exists and is valid JSON" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/api.json"
    
    # Validate JSON syntax
    run jq . "${TEST_DASHBOARD_DIR}/api.json" > /dev/null 2>&1
    assert_success "api.json is not valid JSON"
}

##
# Test: infrastructure.json exists and is valid JSON
##
@test "infrastructure.json exists and is valid JSON" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/infrastructure.json"
    
    # Validate JSON syntax
    run jq . "${TEST_DASHBOARD_DIR}/infrastructure.json" > /dev/null 2>&1
    assert_success "infrastructure.json is not valid JSON"
}

##
# Test: All Grafana dashboards have consistent structure
##
@test "All Grafana dashboards have consistent structure" {
    local dashboards=("overview" "ingestion" "analytics" "wms" "api" "infrastructure")
    
    for dashboard in "${dashboards[@]}"; do
        local json_file="${TEST_DASHBOARD_DIR}/${dashboard}.json"
        assert_file_exists "${json_file}"
        
        # Check for dashboard object
        run jq -e '.dashboard' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing dashboard object"
        
        # Check for title
        run jq -e '.dashboard.title' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing title"
        
        # Check for schemaVersion
        run jq -e '.dashboard.schemaVersion' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing schemaVersion"
    done
}

##
# Test: Grafana dashboards have proper tags
##
@test "Grafana dashboards have proper tags" {
    local dashboards=("overview" "ingestion" "analytics" "wms" "api" "infrastructure")
    
    for dashboard in "${dashboards[@]}"; do
        local json_file="${TEST_DASHBOARD_DIR}/${dashboard}.json"
        
        # Check for tags array
        run jq -e '.dashboard.tags' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing tags"
        
        # Check for "osm" tag
        run jq -e '.dashboard.tags[] | select(. == "osm")' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing 'osm' tag"
    done
}

##
# Test: Grafana dashboards have time configuration
##
@test "Grafana dashboards have time configuration" {
    local dashboards=("overview" "ingestion" "analytics" "wms" "api" "infrastructure")
    
    for dashboard in "${dashboards[@]}"; do
        local json_file="${TEST_DASHBOARD_DIR}/${dashboard}.json"
        
        # Check for time object
        run jq -e '.dashboard.time' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing time configuration"
    done
}

##
# Test: Grafana dashboards have panels
##
@test "Grafana dashboards have panels defined" {
    local dashboards=("overview" "ingestion")
    
    for dashboard in "${dashboards[@]}"; do
        local json_file="${TEST_DASHBOARD_DIR}/${dashboard}.json"
        
        # Check for panels array
        run jq -e '.dashboard.panels | length > 0' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing panels or panels array is empty"
    done
}
