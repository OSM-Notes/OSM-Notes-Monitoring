#!/usr/bin/env bats
#
# Unit Tests: generateMetrics.sh
# Tests for metrics generation script
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="DASHBOARD"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_generateMetrics.log"
    init_logging "${LOG_FILE}" "test_generateMetrics"
    
    # Mock psql command
    # shellcheck disable=SC2317
    mock_psql() {
        local query="${*}"
        if echo "${query}" | grep -q "SELECT.*FROM metrics"; then
            echo '{"metric_name":"test_metric","metric_value":100,"timestamp":"2025-12-27T10:00:00Z"}'
        else
            echo "[]"
        fi
    }
    
    # Create temporary directory for output
    TEST_OUTPUT_DIR=$(mktemp -d)
    export TEST_OUTPUT_DIR
}

teardown() {
    # Cleanup
    rm -rf "${TEST_OUTPUT_DIR:-}"
}

##
# Test: generateMetrics.sh usage
##
@test "generateMetrics.sh shows usage with --help" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --help
    assert_success
    assert [[ "${output}" =~ Usage: ]]
    assert [[ "${output}" =~ generateMetrics.sh ]]
}

##
# Test: generateMetrics.sh generates JSON metrics
##
@test "generateMetrics.sh generates JSON metrics for component" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*FROM.metrics ]]; then
            echo '[{"metric_name":"test_metric","metric_value":100}]'
        else
            echo "[]"
        fi
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json
    assert_success
    assert [[ "${output}" =~ metric_name ]] || [[ "${output}" =~ \[\] ]]
}

##
# Test: generateMetrics.sh generates CSV metrics
##
@test "generateMetrics.sh generates CSV metrics" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*FROM.metrics ]]; then
            echo "metric_name,metric_value,metadata,timestamp"
            echo "test_metric,100,{},2025-12-27T10:00:00Z"
        else
            echo ""
        fi
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion csv
    assert_success
    assert [[ "${output}" =~ metric_name ]] || [[ "${output}" =~ test_metric ]]
}

##
# Test: generateMetrics.sh generates dashboard format
##
@test "generateMetrics.sh generates dashboard format" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*json_agg ]]; then
            echo '[{"metric_name":"test_metric","avg_value":100,"min_value":50,"max_value":150}]'
        else
            echo "[]"
        fi
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion dashboard
    assert_success
    assert [[ "${output}" =~ metric_name ]] || [[ "${output}" =~ \[\] ]]
}

##
# Test: generateMetrics.sh handles all components
##
@test "generateMetrics.sh handles all components" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" all json
    assert_success
}

##
# Test: generateMetrics.sh outputs to file
##
@test "generateMetrics.sh outputs to file" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    local output_file="${TEST_OUTPUT_DIR}/metrics.json"
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" -o "${output_file}" ingestion json
    assert_success
    assert_file_exists "${output_file}"
}

##
# Test: generateMetrics.sh handles time range
##
@test "generateMetrics.sh handles time range parameter" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INTERVAL.*168.hours ]]; then
            echo "[]"
        else
            echo "[]"
        fi
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --time-range 168 ingestion json
    assert_success
}

##
# Test: generateMetrics.sh handles invalid component
##
@test "generateMetrics.sh handles invalid component gracefully" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" invalid_component json
    assert_success  # Should still succeed but return empty data
}

##
# Test: generateMetrics.sh handles database errors
##
@test "generateMetrics.sh handles database errors gracefully" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json
    # Should handle error gracefully
    assert_success  # Script should not fail, just return empty/error data
}
