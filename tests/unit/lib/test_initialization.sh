#!/usr/bin/env bash
#
# Unit Tests: Initialization Functions
# Tests initialization code that runs when TEST_MODE=false
#
# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Sourcing library files

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment - use TEST_MODE=false to allow initialization
    export TEST_MODE=false
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Disable alerts for unit tests (to avoid database calls)
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Mock database functions to avoid real DB calls during initialization
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock psql to avoid database connection attempts
    # shellcheck disable=SC2317
    psql() {
        echo "mocked"
        return 0
    }
    export -f psql
    
    # Source libraries
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/securityFunctions.sh"
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    
    # Ensure config file doesn't exist initially
    local config_file="${BATS_TEST_DIRNAME}/../../../config/alerts.conf"
    if [[ -f "${config_file}" ]]; then
        mv "${config_file}" "${config_file}.bak" 2>/dev/null || true
    fi
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
    
    # Restore config file if it was backed up
    local config_file="${BATS_TEST_DIRNAME}/../../../config/alerts.conf"
    if [[ -f "${config_file}.bak" ]]; then
        mv "${config_file}.bak" "${config_file}" 2>/dev/null || true
    fi
}

##
# Test: init_logging creates log directory
##
@test "init_logging creates log directory when it doesn't exist" {
    local test_log_file="${TEST_LOG_DIR}/test_init.log"
    rm -rf "${TEST_LOG_DIR}"
    
    # Reset LOG_FILE to default before test
    LOG_FILE="/dev/stderr"
    
    # Run init_logging
    init_logging "${test_log_file}" "test_script"
    
    # Verify log directory was created
    assert [ -d "${TEST_LOG_DIR}" ]
    
    # Verify LOG_FILE was set
    assert [ "${LOG_FILE}" == "${test_log_file}" ]
    
    # Verify SCRIPT_NAME was set
    assert [ "${SCRIPT_NAME}" == "test_script" ]
}

##
# Test: init_logging uses existing log directory
##
@test "init_logging uses existing log directory" {
    mkdir -p "${TEST_LOG_DIR}"
    local test_log_file="${TEST_LOG_DIR}/test_init.log"
    
    # Reset LOG_FILE to default before test
    LOG_FILE="/dev/stderr"
    
    # Run init_logging
    init_logging "${test_log_file}" "test_script"
    
    # Verify LOG_FILE was set
    assert [ "${LOG_FILE}" == "${test_log_file}" ]
}

##
# Test: init_logging works without arguments
##
@test "init_logging works without arguments" {
    # Run init_logging without arguments
    run init_logging
    
    # Should succeed
    assert_success
}

##
# Test: init_alerting loads alert configuration
##
@test "init_alerting loads alert configuration" {
    # Backup existing config file if it exists
    local config_file="${BATS_TEST_DIRNAME}/../../../config/alerts.conf"
    local config_backup="${config_file}.test_backup"
    if [[ -f "${config_file}" ]]; then
        cp "${config_file}" "${config_backup}" 2>/dev/null || true
    fi
    
    # Create test alert config file
    mkdir -p "$(dirname "${config_file}")"
    echo "ADMIN_EMAIL=\"test_init@example.com\"" > "${config_file}"
    echo "SEND_ALERT_EMAIL=\"true\"" >> "${config_file}"
    
    # Reset ADMIN_EMAIL
    unset ADMIN_EMAIL
    
    # Run init_alerting
    init_alerting
    
    # Verify ADMIN_EMAIL was set from config file
    assert [ "${ADMIN_EMAIL}" == "test_init@example.com" ]
    
    # Restore original config file
    if [[ -f "${config_backup}" ]]; then
        mv "${config_backup}" "${config_file}" 2>/dev/null || true
    else
        rm -f "${config_file}"
    fi
}

##
# Test: init_alerting sets defaults when config file doesn't exist
##
@test "init_alerting sets defaults when config file doesn't exist" {
    # Backup and remove config file if it exists
    local config_file="${BATS_TEST_DIRNAME}/../../../config/alerts.conf"
    local config_backup="${config_file}.test_backup"
    if [[ -f "${config_file}" ]]; then
        mv "${config_file}" "${config_backup}" 2>/dev/null || true
    fi
    
    # Reset variables
    unset ADMIN_EMAIL
    unset SEND_ALERT_EMAIL
    unset SLACK_ENABLED
    
    # Run init_alerting
    init_alerting
    
    # Verify defaults were set
    assert [ "${ADMIN_EMAIL}" == "admin@example.com" ]
    assert [ "${SEND_ALERT_EMAIL}" == "false" ]
    assert [ "${SLACK_ENABLED}" == "false" ]
    
    # Restore config file if it was backed up
    if [[ -f "${config_backup}" ]]; then
        mv "${config_backup}" "${config_file}" 2>/dev/null || true
    fi
}

##
# Test: init_security initializes security functions
##
@test "init_security initializes security functions" {
    # Run init_security
    run init_security
    
    # Should succeed
    assert_success
}

##
# Test: load_main_config loads configuration file
##
@test "load_main_config loads configuration file" {
    # Create test config file in etc directory
    local project_root="${BATS_TEST_DIRNAME}/../../.."
    local config_file="${project_root}/etc/properties.sh"
    mkdir -p "$(dirname "${config_file}")"
    
    # Backup existing config if it exists
    local config_backup="${config_file}.test_backup"
    if [[ -f "${config_file}" ]]; then
        cp "${config_file}" "${config_backup}" 2>/dev/null || true
    fi
    
    # Create test config
    echo "TEST_VAR=\"test_value\"" > "${config_file}"
    
    # Run load_main_config
    load_main_config
    
    # Verify variable was loaded
    assert [ "${TEST_VAR}" == "test_value" ]
    
    # Restore original config if it existed
    if [[ -f "${config_backup}" ]]; then
        mv "${config_backup}" "${config_file}" 2>/dev/null || true
    else
        rm -f "${config_file}"
    fi
}

##
# Test: load_main_config handles missing config file gracefully
##
@test "load_main_config handles missing config file gracefully" {
    # Backup and remove config file if it exists
    local project_root="${BATS_TEST_DIRNAME}/../../.."
    local config_file="${project_root}/etc/properties.sh"
    local config_backup="${config_file}.test_backup"
    if [[ -f "${config_file}" ]]; then
        mv "${config_file}" "${config_backup}" 2>/dev/null || true
    fi
    
    # Run load_main_config with missing file
    run load_main_config
    
    # Should fail (returns 1 when config file doesn't exist)
    assert_failure
    
    # Restore config file if it existed
    if [[ -f "${config_backup}" ]]; then
        mv "${config_backup}" "${config_file}" 2>/dev/null || true
    fi
}

##
# Test: Initialization code runs when TEST_MODE=false in scripts
##
@test "Script initialization runs when TEST_MODE=false" {
    # Set TEST_MODE=false
    export TEST_MODE=false
    
    # Source a monitor script
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorData.sh" 2>/dev/null || true
    
    # Verify that initialization code paths were executed
    # (The script should have set up logging, etc.)
    assert [ -n "${COMPONENT:-}" ]
}

##
# Test: Multiple initialization calls work correctly
##
@test "Multiple initialization calls work correctly" {
    local log_file1="${TEST_LOG_DIR}/test1.log"
    local log_file2="${TEST_LOG_DIR}/test2.log"
    
    # Reset LOG_FILE to default
    LOG_FILE="/dev/stderr"
    
    # First initialization
    init_logging "${log_file1}" "script1"
    assert [ "${LOG_FILE}" == "${log_file1}" ]
    assert [ "${SCRIPT_NAME}" == "script1" ]
    
    # Second initialization
    init_logging "${log_file2}" "script2"
    assert [ "${LOG_FILE}" == "${log_file2}" ]
    assert [ "${SCRIPT_NAME}" == "script2" ]
}

##
# Test: init_alerting can be called multiple times
##
@test "init_alerting can be called multiple times" {
    # First call
    run init_alerting
    assert_success
    
    # Second call
    run init_alerting
    assert_success
    
    # Should still work
    assert [ -n "${ADMIN_EMAIL:-}" ]
}
