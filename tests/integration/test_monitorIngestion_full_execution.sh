#!/usr/bin/env bash
#
# Integration Tests: monitorIngestion.sh - Full Script Execution
# Tests full script execution with minimal mocking
#
# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Sourcing library files

export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_INGESTION_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_ingestion_full"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment - minimal TEST_MODE to allow more code execution
    export TEST_MODE=false  # Allow initialization code to run
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    export COMPONENT="INGESTION"
    
    # Create test directories
    mkdir -p "${TEST_INGESTION_DIR}/bin"
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export INGESTION_REPO_PATH="${TEST_INGESTION_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Set test configuration
    export INGESTION_ENABLED="true"
    export INGESTION_SCRIPTS_FOUND_THRESHOLD="3"
    export INGESTION_LAST_LOG_AGE_THRESHOLD="24"
    export INGESTION_MAX_ERROR_RATE="5"
    export INGESTION_ERROR_COUNT_THRESHOLD="1000"
    export INGESTION_WARNING_COUNT_THRESHOLD="2000"
    export INGESTION_WARNING_RATE_THRESHOLD="15"
    export INGESTION_DATA_QUALITY_THRESHOLD="95"
    export INGESTION_LATENCY_THRESHOLD="300"
    export INGESTION_DATA_FRESHNESS_THRESHOLD="3600"
    export INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD="95"
    export INFRASTRUCTURE_DISK_THRESHOLD="90"
    export PERFORMANCE_SLOW_QUERY_THRESHOLD="1000"
    
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
    rm -rf "${TEST_INGESTION_DIR}"
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
# Test: Full script execution with health check
##
@test "Full script execution: checks ingestion health" {
    # Execute script directly with --check health
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh" --check health
    
    # Should execute without crashing
    # Status can be 0 (success) or 1 (check failed) but not error
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with performance check
##
@test "Full script execution: checks ingestion performance" {
    # Execute script directly with --check performance
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh" --check performance
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with data-quality check
##
@test "Full script execution: checks data quality" {
    # Execute script directly with --check data-quality
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh" --check data-quality
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with execution-status check
##
@test "Full script execution: checks script execution status" {
    # Create some test scripts in the ingestion bin directory
    mkdir -p "${TEST_INGESTION_DIR}/bin"
    echo "#!/bin/bash" > "${TEST_INGESTION_DIR}/bin/test_script.sh"
    chmod +x "${TEST_INGESTION_DIR}/bin/test_script.sh"
    
    # Execute script directly with --check execution-status
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh" --check execution-status
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution runs all checks
##
@test "Full script execution: runs all checks when no argument" {
    # Create some test scripts and logs
    mkdir -p "${TEST_INGESTION_DIR}/bin"
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    echo "#!/bin/bash" > "${TEST_INGESTION_DIR}/bin/test_script.sh"
    chmod +x "${TEST_INGESTION_DIR}/bin/test_script.sh"
    echo "test log" > "${TEST_INGESTION_DIR}/logs/test.log"
    
    # Execute script directly without arguments (runs all checks)
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh"
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify log file was created
    assert_file_exists "${LOG_DIR}/ingestion.log" || assert_file_exists "${LOG_DIR}/monitorIngestion.log"
}

##
# Test: Full script execution with --help option
##
@test "Full script execution: shows usage with --help" {
    # Execute script with --help
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh" --help
    
    # Should show usage and exit successfully
    assert_success
    assert_output --partial "Usage" || assert_output --partial "Ingestion" || assert_output --partial "monitor"
}

##
# Test: Full script execution with --verbose option
##
@test "Full script execution: runs with verbose logging" {
    # Execute script with --verbose
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh" --verbose --check health
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with --dry-run option
##
@test "Full script execution: runs with dry-run mode" {
    # Execute script with --dry-run
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh" --dry-run --check health
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with latency check
##
@test "Full script execution: checks processing latency" {
    # Execute script directly with --check latency
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh" --check latency
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with error-rate check
##
@test "Full script execution: checks error rate" {
    # Create test log file with some content
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    echo "ERROR: test error" > "${TEST_INGESTION_DIR}/logs/test.log"
    
    # Execute script directly with --check error-rate
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh" --check error-rate
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}
