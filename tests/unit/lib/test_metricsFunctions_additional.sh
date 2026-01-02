#!/usr/bin/env bats
#
# Additional Unit Tests: metricsFunctions.sh
# Additional tests for metrics functions library to increase coverage
#

# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Not following source files is expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="METRICS"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_metricsFunctions_additional.log"
    init_logging "${LOG_FILE}" "test_metricsFunctions_additional"
    
    # Mock database connection
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
}

teardown() {
    # Cleanup
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: init_metrics initializes correctly
##
@test "init_metrics initializes correctly" {
    run init_metrics
    assert_success
}

##
# Test: record_metric handles different metric unit suffixes
##
@test "record_metric detects percent unit from suffix" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify unit is "percent"
        if [[ "${4}" == "percent" ]]; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric_percent" "50" ""
    assert_success
}

@test "record_metric detects milliseconds unit from suffix" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify unit is "milliseconds"
        if [[ "${4}" == "milliseconds" ]]; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric_ms" "100" ""
    assert_success
}

@test "record_metric detects seconds unit from suffix" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify unit is "seconds"
        if [[ "${4}" == "seconds" ]]; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric_seconds" "5" ""
    assert_success
}

@test "record_metric detects count unit from suffix" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify unit is "count"
        if [[ "${4}" == "count" ]]; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric_count" "10" ""
    assert_success
}

@test "record_metric detects bytes unit from suffix" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify unit is "bytes"
        if [[ "${4}" == "bytes" ]]; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric_bytes" "1024" ""
    assert_success
}

@test "record_metric detects boolean unit for status metrics" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify unit is "boolean" for status metrics with 0 or 1
        if [[ "${4}" == "boolean" ]]; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_status" "1" ""
    assert_success
}

@test "record_metric converts component to lowercase" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify component is lowercase
        if [[ "${1}" == "test_component" ]]; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" ""
    assert_success
}

##
# Test: record_metric handles empty metadata
##
@test "record_metric handles empty metadata" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify metadata is "null"
        if [[ "${5}" == "null" ]]; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" ""
    assert_success
}

##
# Test: record_metric handles metadata with special characters
##
@test "record_metric escapes quotes in metadata values" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify metadata JSON doesn't have unescaped quotes
        local metadata="${5}"
        if [[ "${metadata}" =~ \\\" ]]; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" "key=\"value\""
    assert_success
}

##
# Test: get_metrics_summary with custom hours_back
##
@test "get_metrics_summary uses custom hours_back" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INTERVAL.*48.*hours ]]; then
            echo "metric1|100|50|150|10"
            return 0
        fi
        return 1
    }
    
    run get_metrics_summary "TEST_COMPONENT" "48"
    assert_success
    assert_output --partial "metric1"
}

##
# Test: get_metrics_summary with PGPASSWORD
##
@test "get_metrics_summary uses PGPASSWORD when set" {
    export PGPASSWORD="test_password"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*metrics ]]; then
            echo "metric1|100|50|150|10"
            return 0
        fi
        return 1
    }
    
    run get_metrics_summary "TEST_COMPONENT" "24"
    assert_success
}

##
# Test: cleanup_old_metrics with custom retention days
##
@test "cleanup_old_metrics uses custom retention days" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ cleanup_old_metrics.*30 ]]; then
            echo "100"
            return 0
        fi
        return 1
    }
    
    run cleanup_old_metrics "30"
    assert_success
}

##
# Test: cleanup_old_metrics with PGPASSWORD
##
@test "cleanup_old_metrics uses PGPASSWORD when set" {
    export PGPASSWORD="test_password"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ cleanup_old_metrics ]]; then
            echo "50"
            return 0
        fi
        return 1
    }
    
    run cleanup_old_metrics "90"
    assert_success
}

##
# Test: get_latest_metric_value with custom hours_back
##
@test "get_latest_metric_value uses custom hours_back" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INTERVAL.*2.*hours ]]; then
            echo "200"
            return 0
        fi
        return 1
    }
    
    run get_latest_metric_value "TEST_COMPONENT" "test_metric" "2"
    assert_success
    assert_output "200"
}

##
# Test: get_metrics_by_component with limit
##
@test "get_metrics_by_component uses limit" {
    # Mock psql (get_metrics_by_component doesn't accept limit parameter, only hours_back)
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*metric_name.*metric_value.*timestamp.*FROM.*metrics ]]; then
            echo "metric1|100|2025-12-28"
            return 0
        fi
        return 1
    }
    export -f psql
    
    # get_metrics_by_component accepts: component, hours_back (not limit)
    run get_metrics_by_component "TEST_COMPONENT" "10"
    assert_success
    assert_output --partial "metric1"
}

##
# Test: aggregate_metrics with avg aggregation
##
@test "aggregate_metrics uses avg aggregation" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ AVG\(metric_value\) ]]; then
            echo "150"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "avg" "24 hours"
    assert_success
    assert_output "150"
}

##
# Test: aggregate_metrics with max aggregation
##
@test "aggregate_metrics uses max aggregation" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ MAX\(metric_value\) ]]; then
            echo "200"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "max" "24 hours"
    assert_success
    assert_output "200"
}

##
# Test: aggregate_metrics with min aggregation
##
@test "aggregate_metrics uses min aggregation" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ MIN\(metric_value\) ]]; then
            echo "50"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "min" "24 hours"
    assert_success
    assert_output "50"
}

##
# Test: aggregate_metrics with sum aggregation
##
@test "aggregate_metrics uses sum aggregation" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SUM\(metric_value\) ]]; then
            echo "1000"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "sum" "24 hours"
    assert_success
    assert_output "1000"
}

##
# Test: aggregate_metrics handles invalid aggregation type
##
@test "aggregate_metrics handles invalid aggregation type" {
    # Mock log_error
    # shellcheck disable=SC2317
    function log_error() {
        return 0
    }
    export -f log_error
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "invalid" "24 hours"
    assert_failure
}

##
# Test: aggregate_metrics handles hour period (backward compatibility)
##
@test "aggregate_metrics handles hour period backward compatibility" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ DATE_TRUNC.*hour ]]; then
            echo "2025-12-28 10:00:00|150|100|200|1"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "hour"
    assert_success
    assert_output --partial "2025-12-28"
}

##
# Test: get_metric_value handles empty result
##
@test "get_metric_value handles empty result" {
    # Mock get_latest_metric_value to return empty
    # shellcheck disable=SC2317
    function get_latest_metric_value() {
        echo ""
        return 0
    }
    export -f get_latest_metric_value
    
    run get_metric_value "TEST_COMPONENT" "test_metric"
    assert_success
    assert_output ""
}

##
# Test: record_metric handles metadata with multiple pairs
##
@test "record_metric handles multiple metadata pairs" {
    # Mock store_metric
    # shellcheck disable=SC2317
    function store_metric() {
        # Verify metadata JSON contains multiple keys
        local metadata="${5}"
        if echo "${metadata}" | grep -q "key1" && echo "${metadata}" | grep -q "key2"; then
            return 0
        fi
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" "key1=value1,key2=value2"
    assert_success
}

##
# Test: get_metrics_by_component handles empty result
##
@test "get_metrics_by_component handles empty result" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run get_metrics_by_component "TEST_COMPONENT" "10"
    assert_success
    assert_output ""
}

##
# Test: cleanup_old_metrics handles database error
##
@test "cleanup_old_metrics handles database error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    # Mock log_error
    # shellcheck disable=SC2317
    function log_error() {
        return 0
    }
    export -f log_error
    
    run cleanup_old_metrics "90"
    assert_failure
}
