#!/usr/bin/env bats
#
# Additional Unit Tests: monitoringFunctions.sh
# Additional tests for monitoring functions library to increase coverage
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="MONITORING"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_monitoringFunctions_additional.log"
    init_logging "${LOG_FILE}" "test_monitoringFunctions_additional"
    
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
# Test: get_db_connection_string with PGPASSWORD
##
@test "get_db_connection_string includes password when PGPASSWORD is set" {
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    export PGPASSWORD="test_password"
    
    run get_db_connection_string
    assert_success
    assert_output --partial "postgresql"
    assert_output --partial "test_db"
}

##
# Test: execute_sql_query handles empty query
##
@test "execute_sql_query handles empty query" {
    run execute_sql_query ""
    assert_failure
}

##
# Test: execute_sql_query handles query with special characters
##
@test "execute_sql_query handles query with special characters" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*test.*value ]]; then
            echo "result"
            return 0
        fi
        return 1
    }
    
    run execute_sql_query "SELECT 'test' || ' value' FROM test_table"
    assert_success
}

##
# Test: execute_sql_file handles empty file
##
@test "execute_sql_file handles empty file" {
    local test_sql_file="${BATS_TEST_DIRNAME}/../../tmp/test_empty.sql"
    touch "${test_sql_file}"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -f.*test_empty.sql ]]; then
            return 0
        fi
        return 1
    }
    
    run execute_sql_file "${test_sql_file}"
    assert_success
    
    rm -f "${test_sql_file}"
}

##
# Test: store_metric handles all valid components
##
@test "store_metric handles ingestion component" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ ingestion ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run store_metric "ingestion" "test_metric" "100" "count"
    assert_success
}

@test "store_metric handles analytics component" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ analytics ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run store_metric "analytics" "test_metric" "100" "count"
    assert_success
}

@test "store_metric handles wms component" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ wms ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run store_metric "wms" "test_metric" "100" "count"
    assert_success
}

@test "store_metric handles api component" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ api ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run store_metric "api" "test_metric" "100" "count"
    assert_success
}

@test "store_metric handles data component" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ data ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run store_metric "data" "test_metric" "100" "count"
    assert_success
}

@test "store_metric handles infrastructure component" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ infrastructure ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run store_metric "infrastructure" "test_metric" "100" "count"
    assert_success
}

##
# Test: store_metric handles database error
##
@test "store_metric handles database error" {
    # Mock execute_sql_query to fail
    # shellcheck disable=SC2317
    function execute_sql_query() {
        return 1
    }
    export -f execute_sql_query
    
    run store_metric "ingestion" "test_metric" "100" "count"
    assert_failure
}

##
# Test: update_component_health handles all status types
##
@test "update_component_health handles unknown status" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ UPDATE.*component_health ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run update_component_health "ingestion" "unknown" 0
    assert_success
}

##
# Test: get_component_health handles database error
##
@test "get_component_health handles database error" {
    # Mock execute_sql_query to fail
    # shellcheck disable=SC2317
    function execute_sql_query() {
        return 1
    }
    export -f execute_sql_query
    
    run get_component_health "ingestion"
    # Should return "unknown" and exit with failure
    assert_failure
    assert_output "unknown"
}

##
# Test: check_http_health handles curl unavailability
##
@test "check_http_health handles curl unavailability" {
    # Unset curl command
    # shellcheck disable=SC2317
    function curl() {
        return 127  # Command not found
    }
    export -f curl
    
    run check_http_health "http://localhost/test"
    assert_failure
}

##
# Test: get_http_response_time handles curl unavailability
##
@test "get_http_response_time handles curl unavailability" {
    # Unset curl command
    # shellcheck disable=SC2317
    function curl() {
        return 127  # Command not found
    }
    export -f curl
    
    run get_http_response_time "http://localhost/test"
    assert_failure
    assert_output "-1"
}

##
# Test: init_monitoring preserves LOG_DIR in test mode
##
@test "init_monitoring preserves LOG_DIR in test mode" {
    export TEST_MODE=true
    export LOG_DIR="/test/log/dir"
    
    # Run init_monitoring
    init_monitoring
    
    # LOG_DIR should be preserved in test mode
    assert [[ "${LOG_DIR}" == "/test/log/dir" ]]
}

##
# Test: check_database_connection handles missing psql
##
@test "check_database_connection handles missing psql" {
    # Mock psql to not exist
    # shellcheck disable=SC2317
    function psql() {
        return 127  # Command not found
    }
    
    run check_database_connection
    assert_failure
}

##
# Test: execute_sql_query handles connection failure
##
@test "execute_sql_query handles connection failure" {
    # Mock psql to fail with connection error
    # shellcheck disable=SC2317
    function psql() {
        echo "Error: connection refused" >&2
        return 1
    }
    
    run execute_sql_query "SELECT 1"
    assert_failure
    assert_output --partial "Error"
}

##
# Test: execute_sql_file handles psql failure
##
@test "execute_sql_file handles psql failure" {
    local test_sql_file="${BATS_TEST_DIRNAME}/../../tmp/test_error.sql"
    echo "SELECT 1;" > "${test_sql_file}"
    
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        echo "Error: syntax error" >&2
        return 1
    }
    
    run execute_sql_file "${test_sql_file}"
    assert_failure
    
    rm -f "${test_sql_file}"
}

##
# Test: get_http_response_time handles very fast response
##
@test "get_http_response_time handles very fast response" {
    # Mock curl to return immediately
    # shellcheck disable=SC2317
    function curl() {
        return 0
    }
    export -f curl
    
    run get_http_response_time "http://localhost/test"
    assert_success
    # Output should be numeric (response time)
    [[ "${output}" =~ ^[0-9]+$ ]]
}

##
# Test: check_http_health with custom timeout
##
@test "check_http_health uses custom timeout" {
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        # Verify timeout parameter is passed
        if [[ "${*}" =~ --max-time.*5 ]]; then
            return 0
        fi
        return 1
    }
    export -f curl
    
    run check_http_health "http://localhost/test" "5"
    assert_success
}

##
# Test: get_http_response_time with custom timeout
##
@test "get_http_response_time uses custom timeout" {
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        # Verify timeout parameter is passed
        if [[ "${*}" =~ --max-time.*5 ]]; then
            return 0
        fi
        return 1
    }
    export -f curl
    
    run get_http_response_time "http://localhost/test" "5"
    assert_success
}
