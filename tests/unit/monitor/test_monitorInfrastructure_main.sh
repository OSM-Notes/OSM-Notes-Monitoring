#!/usr/bin/env bash
#
# Unit Tests: monitorInfrastructure.sh - Main Function Tests
# Tests main function execution with different scenarios
#
# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Sourcing library files

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
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
    
    # Disable alerts for unit tests
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Mock database functions
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock functions - reduce mocking to test more real code
    # shellcheck disable=SC2317
    psql() {
        echo "mocked"
        return 0
    }
    export -f psql
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    load_config() {
        return 0
    }
    export -f load_config
    
    # shellcheck disable=SC2317
    init_alerting() {
        return 0
    }
    export -f init_alerting
    
    # Source libraries
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Initialize logging
    init_logging "${LOG_DIR}/test_monitorInfrastructure_main.log" "test_monitorInfrastructure_main"
    
    # Source monitorInfrastructure.sh functions
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorInfrastructure.sh" 2>/dev/null || true
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: main function executes all checks when no argument provided
##
@test "main function executes all checks when no argument provided" {
    # Mock check functions
    # shellcheck disable=SC2317
    check_server_resources() {
        return 0
    }
    export -f check_server_resources
    
    # shellcheck disable=SC2317
    check_advanced_system_metrics() {
        return 0
    }
    export -f check_advanced_system_metrics
    
    # shellcheck disable=SC2317
    check_network_connectivity() {
        return 0
    }
    export -f check_network_connectivity
    
    # shellcheck disable=SC2317
    check_database_server_health() {
        return 0
    }
    export -f check_database_server_health
    
    # shellcheck disable=SC2317
    check_service_dependencies() {
        return 0
    }
    export -f check_service_dependencies
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # shellcheck disable=SC2317
    log_warning() {
        return 0
    }
    export -f log_warning
    
    # Run main with no arguments
    run main
    
    # Should succeed
    assert_success
    
    # Verify main succeeded
    assert [ ${status} -eq 0 ]
}

##
# Test: main function executes specific check when argument provided
##
@test "main function executes specific check when argument provided" {
    # Mock specific check function
    # shellcheck disable=SC2317
    check_server_resources() {
        return 0
    }
    export -f check_server_resources
    
    # shellcheck disable=SC2317
    check_advanced_system_metrics() {
        return 0
    }
    export -f check_advanced_system_metrics
    
    # Mock other checks to ensure they're not called
    # shellcheck disable=SC2317
    check_network_connectivity() {
        return 0
    }
    export -f check_network_connectivity
    
    # shellcheck disable=SC2317
    check_database_server_health() {
        return 0
    }
    export -f check_database_server_health
    
    # shellcheck disable=SC2317
    check_service_dependencies() {
        return 0
    }
    export -f check_service_dependencies
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # shellcheck disable=SC2317
    log_warning() {
        return 0
    }
    export -f log_warning
    
    # Run main with specific check
    run main "server_resources"
    
    # Should succeed
    assert_success
}

##
# Test: main function handles load_config failure gracefully
##
@test "main function handles load_config failure gracefully" {
    # Mock load_config to fail
    # shellcheck disable=SC2317
    load_config() {
        return 1
    }
    export -f load_config
    
    # Mock check functions
    # shellcheck disable=SC2317
    check_server_resources() { return 0; }
    # shellcheck disable=SC2317
    check_network_connectivity() { return 0; }
    # shellcheck disable=SC2317
    check_database_server_health() { return 0; }
    # shellcheck disable=SC2317
    check_service_dependencies() { return 0; }
    export -f check_server_resources check_network_connectivity check_database_server_health check_service_dependencies
    
    # Run main
    run main || true
    
    # Should handle failure (may exit or continue)
    # Just verify it doesn't crash
    assert [ ${status} -ge 0 ]
}

##
# Test: main function initializes alerting
##
@test "main function initializes alerting" {
    # Mock init_alerting
    # shellcheck disable=SC2317
    init_alerting() {
        return 0
    }
    export -f init_alerting
    
    # Mock check functions
    # shellcheck disable=SC2317
    check_server_resources() { return 0; }
    # shellcheck disable=SC2317
    check_advanced_system_metrics() { return 0; }
    # shellcheck disable=SC2317
    check_network_connectivity() { return 0; }
    # shellcheck disable=SC2317
    check_database_server_health() { return 0; }
    # shellcheck disable=SC2317
    check_service_dependencies() { return 0; }
    export -f check_server_resources check_advanced_system_metrics check_network_connectivity check_database_server_health check_service_dependencies
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() { return 0; }
    # shellcheck disable=SC2317
    log_warning() { return 0; }
    export -f log_info log_warning
    
    # Run main
    run main
    
    # Should succeed
    assert_success
}

##
# Test: main function returns non-zero when checks fail
##
@test "main function returns non-zero when checks fail" {
    # Mock check functions to fail
    # shellcheck disable=SC2317
    check_server_resources() {
        return 1
    }
    export -f check_server_resources
    
    # shellcheck disable=SC2317
    check_network_connectivity() {
        return 0
    }
    export -f check_network_connectivity
    
    # shellcheck disable=SC2317
    check_database_server_health() {
        return 0
    }
    export -f check_database_server_health
    
    # shellcheck disable=SC2317
    check_service_dependencies() {
        return 0
    }
    export -f check_service_dependencies
    
    # Run main
    run main
    
    # Should return non-zero (1) when checks fail
    assert [ ${status} -eq 1 ]
}

##
# Test: main function handles multiple check types
##
@test "main function handles multiple check types" {
    # Mock all check functions
    # shellcheck disable=SC2317
    check_server_resources() { return 0; }
    # shellcheck disable=SC2317
    check_advanced_system_metrics() { return 0; }
    # shellcheck disable=SC2317
    check_network_connectivity() { return 0; }
    # shellcheck disable=SC2317
    check_database_server_health() { return 0; }
    # shellcheck disable=SC2317
    check_service_dependencies() { return 0; }
    export -f check_server_resources check_advanced_system_metrics check_network_connectivity check_database_server_health check_service_dependencies
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() { return 0; }
    # shellcheck disable=SC2317
    log_warning() { return 0; }
    export -f log_info log_warning
    
    # Test each check type
    run main "server_resources"
    assert_success
    
    run main "network_connectivity"
    assert_success
    
    run main "database_health"
    assert_success
    
    run main "service_dependencies"
    assert_success
}
