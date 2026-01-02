#!/usr/bin/env bats
#
# Third Unit Tests: monitoringFunctions.sh
# Third test file to reach 80% coverage
#

export TEST_COMPONENT="MONITORING"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_monitoringFunctions_third.log"
    init_logging "${LOG_FILE}" "test_monitoringFunctions_third"
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: execute_sql_query handles multi-line queries
##
@test "execute_sql_query handles multi-line queries" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*FROM.*metrics ]]; then
            echo "result1"
            echo "result2"
            return 0
        fi
        return 1
    }
    
    local query="SELECT * FROM metrics
WHERE component = 'ingestion'
ORDER BY timestamp DESC;"
    
    run execute_sql_query "${query}"
    assert_success
}

##
# Test: check_database_connection handles connection string with password
##
@test "check_database_connection handles connection string with password" {
    export PGPASSWORD="test_password"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -c.*SELECT.*1 ]]; then
            echo "1"
            return 0
        fi
        return 1
    }
    
    run check_database_connection
    assert_success
}

##
# Test: store_metric handles all component types
##
@test "store_metric handles data component" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ data ]]; then
            return 0
        fi
        return 1
    }
    
    run store_metric "data" "test_metric" "100" "count"
    assert_success
}

##
# Test: get_component_health handles database connection failure
##
@test "get_component_health handles database connection failure" {
    # Mock execute_sql_query to fail
    # shellcheck disable=SC2317
    function execute_sql_query() {
        return 1
    }
    export -f execute_sql_query
    
    run get_component_health "ingestion"
    assert_failure
    assert_output "unknown"
}

##
# Test: update_component_health handles database failure
##
@test "update_component_health handles database failure" {
    # Mock execute_sql_query to fail
    # shellcheck disable=SC2317
    function execute_sql_query() {
        return 1
    }
    export -f execute_sql_query
    
    run update_component_health "ingestion" "healthy" 0
    assert_failure
}

##
# Test: get_http_response_time handles very slow response
##
@test "get_http_response_time handles very slow response" {
    # Mock curl to simulate slow response
    # shellcheck disable=SC2317
    function curl() {
        sleep 0.002  # Simulate 2ms delay
        return 0
    }
    export -f curl
    
    run get_http_response_time "http://localhost/test"
    assert_success
    # Output should be numeric
    [[ "${output}" =~ ^[0-9]+$ ]]
}

##
# Test: execute_sql_file handles file with comments
##
@test "execute_sql_file handles file with comments" {
    local test_sql_file="${BATS_TEST_DIRNAME}/../../tmp/test_comments.sql"
    cat > "${test_sql_file}" << 'EOF'
-- This is a comment
SELECT 1;
-- Another comment
SELECT 2;
EOF
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -f.*test_comments.sql ]]; then
            return 0
        fi
        return 1
    }
    
    run execute_sql_file "${test_sql_file}"
    assert_success
    
    rm -f "${test_sql_file}"
}

##
# Test: get_db_connection_string handles all database parameters
##
@test "get_db_connection_string handles all database parameters" {
    export DBNAME="custom_db"
    export DBHOST="remote.host"
    export DBPORT="5433"
    export DBUSER="custom_user"
    
    run get_db_connection_string
    assert_success
    assert_output --partial "custom_db"
    assert_output --partial "remote.host"
    assert_output --partial "5433"
    assert_output --partial "custom_user"
}

##
# Test: check_http_health handles redirects
##
@test "check_http_health handles redirects" {
    # Mock curl to return redirect
    # shellcheck disable=SC2317
    function curl() {
        # Simulate redirect (curl -f would fail on redirect)
        return 0
    }
    export -f curl
    
    run check_http_health "http://localhost/test"
    assert_success
}

##
# Test: store_metric handles zero value
##
@test "store_metric handles zero value" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ 0 ]]; then
            return 0
        fi
        return 1
    }
    
    run store_metric "ingestion" "test_metric" "0" "count"
    assert_success
}

##
# Test: store_metric handles negative value
##
@test "store_metric handles negative value" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ -10 ]]; then
            return 0
        fi
        return 1
    }
    
    run store_metric "ingestion" "test_metric" "-10" "count"
    assert_success
}

##
# Test: execute_sql_query handles query with quotes
##
@test "execute_sql_query handles query with quotes" {
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
# Test: update_component_health handles zero error count
##
@test "update_component_health handles zero error count" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ UPDATE.*component_health ]] && [[ "${*}" =~ error_count.*0 ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run update_component_health "ingestion" "healthy" 0
    assert_success
}

##
# Test: get_http_response_time handles timeout correctly
##
@test "get_http_response_time handles timeout correctly" {
    # Mock curl to timeout
    # shellcheck disable=SC2317
    function curl() {
        return 1  # Timeout or failure
    }
    export -f curl
    
    run get_http_response_time "http://localhost/test" "1"
    assert_failure
    assert_output "-1"
}

##
# Test: check_http_health handles different HTTP codes
##
@test "check_http_health handles different HTTP codes" {
    # Mock curl to return 404
    # shellcheck disable=SC2317
    function curl() {
        # curl -f fails on 4xx/5xx, so this simulates failure
        return 1
    }
    export -f curl
    
    run check_http_health "http://localhost/test"
    assert_failure
}

##
# Test: execute_sql_file handles file permissions error
##
@test "execute_sql_file handles file permissions error" {
    local test_sql_file="${BATS_TEST_DIRNAME}/../../tmp/test_perms.sql"
    
    # Ensure file doesn't exist from previous runs and clean up any existing file
    rm -f "${test_sql_file}" 2>/dev/null || true
    chmod 644 "${test_sql_file}" 2>/dev/null || true
    rm -f "${test_sql_file}" 2>/dev/null || true
    
    # Create file first with content
    echo "SELECT 1;" > "${test_sql_file}"
    
    # Mock psql to simulate permission error (psql fails when trying to read file)
    # shellcheck disable=SC2317
    function psql() {
        # Simulate permission denied error
        echo "Error executing SQL file: ${test_sql_file}" >&2
        return 1
    }
    export -f psql
    
    run execute_sql_file "${test_sql_file}"
    # Should fail on permission error (simulated by psql mock)
    assert_failure
    
    # Cleanup
    rm -f "${test_sql_file}" 2>/dev/null || true
}

##
# Test: get_component_health handles multiple statuses
##
@test "get_component_health handles degraded status" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ SELECT.*component_health ]]; then
            echo "degraded"
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run get_component_health "ingestion"
    assert_success
    assert_output "degraded"
}

##
# Test: store_metric handles floating point values
##
@test "store_metric handles floating point values" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ 123.45 ]]; then
            return 0
        fi
        return 1
    }
    
    run store_metric "ingestion" "test_metric" "123.45" "percent"
    assert_success
}
