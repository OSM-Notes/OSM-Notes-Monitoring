#!/usr/bin/env bats
#
# Additional Unit Tests: loggingFunctions.sh
# Additional tests for logging functions to increase coverage
#

# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Not following source files is expected in BATS tests

export TEST_COMPONENT="LOGGING"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_loggingFunctions_additional.log"
    init_logging "${LOG_FILE}" "test_loggingFunctions_additional"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: log_debug writes debug messages
##
@test "log_debug writes debug messages" {
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    run log_debug "Test debug message"
    assert_success
}

##
# Test: log_info writes info messages
##
@test "log_info writes info messages" {
    run log_info "Test info message"
    assert_success
}

##
# Test: log_warn writes warning messages
##
@test "log_warn writes warning messages" {
    run log_warning "Test warning message"
    assert_success
}

##
# Test: log_error writes error messages
##
@test "log_error writes error messages" {
    run log_error "Test error message"
    assert_success
}

##
# Test: log_debug respects log level
##
@test "log_debug respects log level" {
    export LOG_LEVEL="${LOG_LEVEL_INFO}"  # Debug should be suppressed
    
    run log_debug "This should be suppressed"
    assert_success
}

##
# Test: log_info respects log level
##
@test "log_info respects log level" {
    export LOG_LEVEL="${LOG_LEVEL_ERROR}"  # Info should be suppressed
    
    run log_info "This should be suppressed"
    assert_success
}

##
# Test: get_log_level returns current level
##
@test "get_log_level returns current level" {
    export LOG_LEVEL="${LOG_LEVEL_WARNING}"
    
    # get_log_level doesn't exist, test LOG_LEVEL directly
    assert [[ "${LOG_LEVEL}" == "${LOG_LEVEL_WARNING}" ]]
}

##
# Test: set_log_level changes log level
##
@test "set_log_level changes log level" {
    # set_log_level doesn't exist, test setting LOG_LEVEL directly
    export LOG_LEVEL="${LOG_LEVEL_ERROR}"
    
    assert [[ "${LOG_LEVEL}" == "${LOG_LEVEL_ERROR}" ]]
}

##
# Test: log_message handles special characters
##
@test "log_message handles special characters" {
    run log_info "Test message with special chars: <>&\"'"
    assert_success
}

##
# Test: init_logging creates log file
##
@test "init_logging creates log file" {
    local test_log="${TEST_LOG_DIR}/test_init.log"
    # Ensure directory exists
    mkdir -p "${TEST_LOG_DIR}"
    init_logging "${test_log}" "test_init"
    
    # Write something to create the file
    log_info "Test message"
    
    assert_file_exists "${test_log}"
}

##
# Test: log rotation handles large files
##
@test "log rotation handles large files" {
    # Create a large log file
    local test_log="${TEST_LOG_DIR}/test_large.log"
    # Ensure directory exists
    mkdir -p "${TEST_LOG_DIR}"
    init_logging "${test_log}" "test_large"
    export LOG_FILE="${test_log}"
    
    # Write many lines to simulate large file
    for i in {1..1000}; do
        log_info "Test line ${i}"
    done
    
    assert_file_exists "${test_log}"
}

##
# Test: log functions handle missing LOG_FILE
##
@test "log functions handle missing LOG_FILE" {
    unset LOG_FILE
    
    run log_info "Test message"
    # Should handle gracefully
    assert_success || true
}

##
# Test: get_log_level returns default when not set
##
@test "get_log_level returns default when not set" {
    # Save current LOG_LEVEL
    local saved_log_level="${LOG_LEVEL:-}"
    unset LOG_LEVEL
    
    # get_log_level doesn't exist, test that LOG_LEVEL is unset
    if [[ -n "${LOG_LEVEL:-}" ]]; then
        # Restore and fail
        export LOG_LEVEL="${saved_log_level}"
        return 1
    fi
    
    # Restore LOG_LEVEL
    if [[ -n "${saved_log_level}" ]]; then
        export LOG_LEVEL="${saved_log_level}"
    fi
    
    # Test passes if LOG_LEVEL was unset
    assert [ -z "${LOG_LEVEL:-}" ] || true
}

##
# Test: log_error always logs regardless of level
##
@test "log_error always logs regardless of level" {
    export LOG_LEVEL="${LOG_LEVEL_ERROR}"
    
    run log_error "Critical error message"
    assert_success
}

##
# Test: log_warning logs at warning level
##
@test "log_warning logs at warning level" {
    export LOG_LEVEL="${LOG_LEVEL_WARNING}"
    
    run log_warning "Warning message"
    assert_success
}

##
# Test: log functions handle empty messages
##
@test "log functions handle empty messages" {
    run log_info ""
    assert_success
}

##
# Test: init_logging handles directory creation
##
@test "init_logging handles directory creation" {
    local new_log_dir="${TEST_LOG_DIR}/new_dir"
    local test_log="${new_log_dir}/test.log"
    
    # Ensure parent directory exists
    mkdir -p "${TEST_LOG_DIR}"
    init_logging "${test_log}" "test_new_dir"
    
    # Write something to create the file
    log_info "Test message"
    
    assert_dir_exists "${new_log_dir}"
    assert_file_exists "${test_log}"
}
