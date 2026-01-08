#!/usr/bin/env bash
#
# Integration Tests: monitorInfrastructure.sh - Full Script Execution
# Tests full script execution with minimal mocking
#
# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Sourcing library files

export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment - minimal TEST_MODE to allow more code execution
    export TEST_MODE=false  # Allow initialization code to run
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    export COMPONENT="INFRASTRUCTURE"
    
    # Create test directories
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Set test configuration
    export INFRASTRUCTURE_ENABLED="true"
    export INFRASTRUCTURE_CPU_THRESHOLD="80"
    export INFRASTRUCTURE_MEMORY_THRESHOLD="85"
    export INFRASTRUCTURE_DISK_THRESHOLD="90"
    export INFRASTRUCTURE_CHECK_TIMEOUT="30"
    export INFRASTRUCTURE_NETWORK_HOSTS="localhost,127.0.0.1"
    export INFRASTRUCTURE_SERVICE_DEPENDENCIES="postgresql"
    
    # Database configuration - use real database if available
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-${USER:-postgres}}"
    
    # Disable email/Slack for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Use real psql if database is available, otherwise mock
    if check_database_connection 2>/dev/null; then
        # Real database available - use real psql
        export USE_REAL_DB=true
    else
        # Mock psql
        # shellcheck disable=SC2317
        psql() {
            echo "mocked"
            return 0
        }
        export -f psql
        export USE_REAL_DB=false
    fi
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Skip if database not available (for tests that need it)
##
skip_if_database_not_available() {
    if [[ "${USE_REAL_DB}" != "true" ]]; then
        skip "Database not available for full execution test"
    fi
}

##
# Test: Full script execution with server resources check
##
@test "Full script execution: checks server resources" {
    # Execute script directly with --check server_resources
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorInfrastructure.sh" --check server_resources
    
    # Should execute without crashing
    # Status can be 0 (success) or 1 (check failed) but not error
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with network connectivity check
##
@test "Full script execution: checks network connectivity" {
    # Execute script directly with --check network_connectivity
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorInfrastructure.sh" --check network_connectivity
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with database health check
##
@test "Full script execution: checks database health" {
    # Execute script directly with --check database_health
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorInfrastructure.sh" --check database_health
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with service dependencies check
##
@test "Full script execution: checks service dependencies" {
    # Execute script directly with --check service_dependencies
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorInfrastructure.sh" --check service_dependencies
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution runs all checks
##
@test "Full script execution: runs all checks when no argument" {
    # Execute script directly without arguments (runs all checks)
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorInfrastructure.sh"
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify log file was created
    assert_file_exists "${LOG_DIR}/infrastructure.log" || assert_file_exists "${LOG_DIR}/monitorInfrastructure.log"
}

##
# Test: Full script execution with --help option
##
@test "Full script execution: shows usage with --help" {
    # Execute script with --help
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorInfrastructure.sh" --help
    
    # Should show usage and exit successfully
    assert_success
    assert_output --partial "Usage" || assert_output --partial "Infrastructure" || assert_output --partial "monitor"
}

##
# Test: Full script execution with --verbose option
##
@test "Full script execution: runs with verbose logging" {
    # Execute script with --verbose
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorInfrastructure.sh" --verbose --check server_resources
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with --quiet option
##
@test "Full script execution: runs with quiet mode" {
    # Execute script with --quiet
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorInfrastructure.sh" --quiet --check server_resources
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}
