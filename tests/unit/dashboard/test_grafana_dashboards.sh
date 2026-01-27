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
    
    # Check for title (overview.json has structure at root level, not under .dashboard)
    run jq -e '.title' "${TEST_DASHBOARD_DIR}/overview.json" > /dev/null 2>&1
    assert_success "overview.json missing title"
    
    # Check for panels
    run jq -e '.panels' "${TEST_DASHBOARD_DIR}/overview.json" > /dev/null 2>&1
    assert_success "overview.json missing panels"
    
    # Check for schemaVersion
    run jq -e '.schemaVersion' "${TEST_DASHBOARD_DIR}/overview.json" > /dev/null 2>&1
    assert_success "overview.json missing schemaVersion"
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
    
    # Check for title (structure is at root level, not under .dashboard)
    run jq -e '.title' "${TEST_DASHBOARD_DIR}/ingestion.json" > /dev/null 2>&1
    assert_success "ingestion.json missing title"
    
    # Check for panels
    run jq -e '.panels' "${TEST_DASHBOARD_DIR}/ingestion.json" > /dev/null 2>&1
    assert_success "ingestion.json missing panels"
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
        
        # Check for title (structure is at root level, not under .dashboard)
        run jq -e '.title' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing title"
        
        # Check for schemaVersion
        run jq -e '.schemaVersion' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing schemaVersion"
        
        # Check for panels
        run jq -e '.panels' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing panels"
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
        run jq -e '.tags' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing tags"
        
        # Check for "osm" tag
        run jq -e '.tags[] | select(. == "osm")' "${json_file}" > /dev/null 2>&1
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
        run jq -e '.time' "${json_file}" > /dev/null 2>&1
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
        run jq -e '.panels | length > 0' "${json_file}" > /dev/null 2>&1
        assert_success "${dashboard}.json missing panels or panels array is empty"
    done
}
