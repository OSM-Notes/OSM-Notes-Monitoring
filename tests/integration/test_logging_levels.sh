#!/usr/bin/env bash
#
# Integration Tests: Logging Levels
# Tests logging functionality with different log levels
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"

# Test directory for log files
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"

setup() {
    # Create test log directory
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test log file
    export LOG_FILE="${TEST_LOG_DIR}/test.log"
    
    # Reset log level to default
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
}

teardown() {
    # Clean up test log files
    rm -rf "${TEST_LOG_DIR}"
}

@test "log_info writes to log file when LOG_LEVEL is INFO" {
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    log_info "Test info message"
    
    assert_file_exists "${LOG_FILE}"
    assert_file_contains "${LOG_FILE}" "INFO"
    assert_file_contains "${LOG_FILE}" "Test info message"
}

@test "log_debug does not write when LOG_LEVEL is INFO" {
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    log_debug "Test debug message"
    
    if [[ -f "${LOG_FILE}" ]]; then
        refute_file_contains "${LOG_FILE}" "DEBUG"
        refute_file_contains "${LOG_FILE}" "Test debug message"
    fi
}

@test "log_debug writes when LOG_LEVEL is DEBUG" {
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    log_debug "Test debug message"
    
    assert_file_exists "${LOG_FILE}"
    assert_file_contains "${LOG_FILE}" "DEBUG"
    assert_file_contains "${LOG_FILE}" "Test debug message"
}

@test "log_warning writes when LOG_LEVEL is INFO" {
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    log_warning "Test warning message"
    
    assert_file_exists "${LOG_FILE}"
    assert_file_contains "${LOG_FILE}" "WARNING"
    assert_file_contains "${LOG_FILE}" "Test warning message"
}

@test "log_error writes when LOG_LEVEL is INFO" {
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    log_error "Test error message"
    
    assert_file_exists "${LOG_FILE}"
    assert_file_contains "${LOG_FILE}" "ERROR"
    assert_file_contains "${LOG_FILE}" "Test error message"
}

@test "log_warning writes when LOG_LEVEL is WARNING" {
    export LOG_LEVEL="${LOG_LEVEL_WARNING}"
    
    log_warning "Test warning message"
    
    assert_file_exists "${LOG_FILE}"
    assert_file_contains "${LOG_FILE}" "WARNING"
    assert_file_contains "${LOG_FILE}" "Test warning message"
}

@test "log_info does not write when LOG_LEVEL is WARNING" {
    export LOG_LEVEL="${LOG_LEVEL_WARNING}"
    
    log_info "Test info message"
    
    if [[ -f "${LOG_FILE}" ]]; then
        refute_file_contains "${LOG_FILE}" "INFO"
        refute_file_contains "${LOG_FILE}" "Test info message"
    fi
}

@test "log_error writes when LOG_LEVEL is ERROR" {
    export LOG_LEVEL="${LOG_LEVEL_ERROR}"
    
    log_error "Test error message"
    
    assert_file_exists "${LOG_FILE}"
    assert_file_contains "${LOG_FILE}" "ERROR"
    assert_file_contains "${LOG_FILE}" "Test error message"
}

@test "log_warning does not write when LOG_LEVEL is ERROR" {
    export LOG_LEVEL="${LOG_LEVEL_ERROR}"
    
    log_warning "Test warning message"
    
    if [[ -f "${LOG_FILE}" ]]; then
        refute_file_contains "${LOG_FILE}" "WARNING"
        refute_file_contains "${LOG_FILE}" "Test warning message"
    fi
}

@test "log_info does not write when LOG_LEVEL is ERROR" {
    export LOG_LEVEL="${LOG_LEVEL_ERROR}"
    
    log_info "Test info message"
    
    if [[ -f "${LOG_FILE}" ]]; then
        refute_file_contains "${LOG_FILE}" "INFO"
        refute_file_contains "${LOG_FILE}" "Test info message"
    fi
}

@test "log_debug does not write when LOG_LEVEL is ERROR" {
    export LOG_LEVEL="${LOG_LEVEL_ERROR}"
    
    log_debug "Test debug message"
    
    if [[ -f "${LOG_FILE}" ]]; then
        refute_file_contains "${LOG_FILE}" "DEBUG"
        refute_file_contains "${LOG_FILE}" "Test debug message"
    fi
}

@test "all log levels write when LOG_LEVEL is DEBUG" {
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    log_debug "Debug message"
    log_info "Info message"
    log_warning "Warning message"
    log_error "Error message"
    
    assert_file_exists "${LOG_FILE}"
    assert_file_contains "${LOG_FILE}" "DEBUG"
    assert_file_contains "${LOG_FILE}" "INFO"
    assert_file_contains "${LOG_FILE}" "WARNING"
    assert_file_contains "${LOG_FILE}" "ERROR"
}

@test "log messages include timestamp" {
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    log_info "Test message"
    
    assert_file_exists "${LOG_FILE}"
    # Check for timestamp format YYYY-MM-DD HH:MM:SS (without brackets)
    assert_file_matches "${LOG_FILE}" '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'
}

@test "log messages include script name when set" {
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    export SCRIPT_NAME="TEST_COMPONENT"
    
    log_info "Test message"
    
    assert_file_exists "${LOG_FILE}"
    assert_file_contains "${LOG_FILE}" "TEST_COMPONENT"
}

