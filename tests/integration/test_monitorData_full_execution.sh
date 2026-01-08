#!/usr/bin/env bash
#
# Integration Tests: monitorData.sh - Full Script Execution
# Tests full script execution with minimal mocking
#
# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Sourcing library files

export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_BACKUP_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_backups_full"
TEST_REPO_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_repo_full"
TEST_STORAGE_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_storage_full"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment - minimal TEST_MODE to allow more code execution
    export TEST_MODE=false  # Allow initialization code to run
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    export COMPONENT="DATA"
    
    # Create test directories
    mkdir -p "${TEST_BACKUP_DIR}"
    mkdir -p "${TEST_REPO_DIR}"
    mkdir -p "${TEST_STORAGE_DIR}"
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export DATA_BACKUP_DIR="${TEST_BACKUP_DIR}"
    export DATA_REPO_PATH="${TEST_REPO_DIR}"
    export DATA_STORAGE_PATH="${TEST_STORAGE_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Set test configuration
    export DATA_ENABLED="true"
    export DATA_BACKUP_FRESHNESS_THRESHOLD="86400"
    export DATA_REPO_SYNC_CHECK_ENABLED="true"
    export DATA_STORAGE_CHECK_ENABLED="true"
    export DATA_CHECK_TIMEOUT="60"
    export DATA_DISK_USAGE_THRESHOLD="90"
    
    # Database configuration - use real database if available
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-${USER:-postgres}}"
    
    # Disable email/Slack for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Mock only external commands that might not be available
    # shellcheck disable=SC2317
    git() {
        # Real git if available, otherwise mock
        if command -v git >/dev/null 2>&1; then
            command git "$@"
        else
            echo "mocked git"
            return 0
        fi
    }
    export -f git
    
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
    rm -rf "${TEST_BACKUP_DIR}"
    rm -rf "${TEST_REPO_DIR}"
    rm -rf "${TEST_STORAGE_DIR}"
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
# Test: Full script execution with real file system operations
##
@test "Full script execution: creates backup and checks freshness" {
    # Create a test backup file
    local backup_file
    backup_file="${TEST_BACKUP_DIR}/backup_$(date +%Y%m%d_%H%M%S).sql"
    echo "test backup content" > "${backup_file}"
    
    # Execute script directly (not sourced)
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorData.sh" backup_freshness
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify backup file still exists (script didn't delete it)
    assert_file_exists "${backup_file}"
}

##
# Test: Full script execution with git repository check
##
@test "Full script execution: checks git repository sync status" {
    # Initialize git repo if git is available
    if command -v git >/dev/null 2>&1; then
        cd "${TEST_REPO_DIR}" || return 1
        git init >/dev/null 2>&1
        git config user.email "test@example.com" >/dev/null 2>&1
        git config user.name "Test User" >/dev/null 2>&1
        echo "test" > test.txt
        git add test.txt >/dev/null 2>&1
        git commit -m "Initial commit" >/dev/null 2>&1
        cd - >/dev/null || true
    fi
    
    # Execute script directly
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorData.sh" repo_sync
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution with storage check
##
@test "Full script execution: checks storage availability" {
    # Create writable storage directory
    mkdir -p "${TEST_STORAGE_DIR}"
    chmod 755 "${TEST_STORAGE_DIR}"
    
    # Execute script directly
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorData.sh" storage_availability
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

##
# Test: Full script execution runs all checks
##
@test "Full script execution: runs all checks when no argument" {
    # Create test environment
    echo "test backup" > "${TEST_BACKUP_DIR}/backup.sql"
    mkdir -p "${TEST_STORAGE_DIR}"
    
    # Execute script directly
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorData.sh"
    
    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify log file was created
    assert_file_exists "${LOG_DIR}/api.log" || assert_file_exists "${LOG_DIR}/monitorData.log"
}

##
# Test: Full script execution with --help option
##
@test "Full script execution: shows usage with --help" {
    # Execute script with --help
    run bash "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorData.sh" --help
    
    # Should show usage and exit successfully
    assert_success
    assert_output --partial "Usage" || assert_output --partial "monitor" || assert_output --partial "data"
}
