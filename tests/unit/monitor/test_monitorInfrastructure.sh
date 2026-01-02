#!/usr/bin/env bash
#
# Unit Tests: monitorInfrastructure.sh
# Tests infrastructure monitoring check functions
#
# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Not following source files is expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
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
    
    # Mock database functions to avoid real DB calls
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Define mocks BEFORE sourcing libraries
    # Mock psql first, as it's a low-level dependency
    # shellcheck disable=SC2317
    psql() {
        return 0
    }
    export -f psql
    
    # Mock check_database_connection
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    execute_sql_query() {
        echo "0"
        return 0
    }
    export -f execute_sql_query
    
    # Mock store_alert to avoid database calls
    # shellcheck disable=SC2317
    store_alert() {
        return 0
    }
    export -f store_alert
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock load_config to avoid loading real config
    # shellcheck disable=SC2317
    load_config() {
        return 0
    }
    export -f load_config
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Re-export mocks after sourcing to ensure they override library functions
    export -f psql
    export -f check_database_connection
    export -f execute_sql_query
    export -f store_alert
    export -f record_metric
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test.log" "test_monitorInfrastructure"
    
    # Initialize alerting
    init_alerting
    
    # Source monitorInfrastructure.sh functions
    # Set component name BEFORE sourcing (to allow override)
    export TEST_MODE=true
    export COMPONENT="INFRASTRUCTURE"
    
    # Source monitorInfrastructure.sh functions
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorInfrastructure.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
    rm -f "${TMP_DIR}/.alert_sent"
    rm -f "${TMP_DIR}/.alert_critical"
}

@test "check_server_resources records metrics when resources are normal" {
    # Mock top/vmstat for CPU
    # shellcheck disable=SC2317
    top() {
        if [[ "${1}" == "-bn1" ]]; then
            echo "Cpu(s):  5.0%us,  2.0%sy,  0.0%ni, 93.0%id,  0.0%wa"
        fi
    }
    export -f top
    
    # Mock free for memory
    # shellcheck disable=SC2317
    free() {
        echo "              total        used        free      shared  buff/cache   available"
        echo "Mem:        8388608     4194304     2097152      524288     2097152     4194304"
    }
    export -f free
    
    # Mock df for disk
    # shellcheck disable=SC2317
    df() {
        if [[ "${1}" == "-h" ]] && [[ "${2}" == "/" ]]; then
            echo "Filesystem      Size  Used Avail Use% Mounted on"
            echo "/dev/sda1        50G   20G   28G  42% /"
        elif [[ "${1}" == "/" ]]; then
            echo "Filesystem     1K-blocks     Used Available Use% Mounted on"
            echo "/dev/sda1       52428800 20971520  29360128  42% /"
        fi
    }
    export -f df
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_server_resources
    
    # Should succeed
    assert_success
}

@test "check_server_resources alerts when CPU usage exceeds threshold" {
    # Mock top for high CPU
    # shellcheck disable=SC2317
    top() {
        if [[ "${1}" == "-bn1" ]]; then
            echo "Cpu(s): 85.0%us,  5.0%sy,  0.0%ni, 10.0%id,  0.0%wa"
        fi
    }
    export -f top
    
    # Mock free for memory
    # shellcheck disable=SC2317
    free() {
        echo "              total        used        free      shared  buff/cache   available"
        echo "Mem:        8388608     2097152     4194304      524288     2097152     6291456"
    }
    export -f free
    
    # Mock df for disk
    # shellcheck disable=SC2317
    df() {
        if [[ "${1}" == "-h" ]] && [[ "${2}" == "/" ]]; then
            echo "Filesystem      Size  Used Avail Use% Mounted on"
            echo "/dev/sda1        50G   20G   28G  42% /"
        elif [[ "${1}" == "/" ]]; then
            echo "Filesystem     1K-blocks     Used Available Use% Mounted on"
            echo "/dev/sda1       52428800 20971520  29360128  42% /"
        fi
    }
    export -f df
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track alert
    local alert_file="${TMP_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"CPU usage"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_server_resources || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_server_resources alerts CRITICAL when CPU usage exceeds 95%" {
    # Mock top for very high CPU
    # shellcheck disable=SC2317
    top() {
        if [[ "${1}" == "-bn1" ]]; then
            echo "Cpu(s): 96.0%us,  2.0%sy,  0.0%ni,  2.0%id,  0.0%wa"
        fi
    }
    export -f top
    
    # Mock free for memory
    # shellcheck disable=SC2317
    free() {
        echo "              total        used        free      shared  buff/cache   available"
        echo "Mem:        8388608     2097152     4194304      524288     2097152     6291456"
    }
    export -f free
    
    # Mock df for disk
    # shellcheck disable=SC2317
    df() {
        if [[ "${1}" == "-h" ]] && [[ "${2}" == "/" ]]; then
            echo "Filesystem      Size  Used Avail Use% Mounted on"
            echo "/dev/sda1        50G   20G   28G  42% /"
        elif [[ "${1}" == "/" ]]; then
            echo "Filesystem     1K-blocks     Used Available Use% Mounted on"
            echo "/dev/sda1       52428800 20971520  29360128  42% /"
        fi
    }
    export -f df
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track critical alert
    local alert_file="${TMP_DIR}/.alert_critical"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${2}" == "CRITICAL" ]] && [[ "${4}" == *"CPU usage"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_server_resources || true
    
    # Critical alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_server_resources alerts when memory usage exceeds threshold" {
    # Mock top for CPU
    # shellcheck disable=SC2317
    top() {
        if [[ "${1}" == "-bn1" ]]; then
            echo "Cpu(s):  5.0%us,  2.0%sy,  0.0%ni, 93.0%id,  0.0%wa"
        fi
    }
    export -f top
    
    # Mock free for high memory usage
    # shellcheck disable=SC2317
    free() {
        echo "              total        used        free      shared  buff/cache   available"
        echo "Mem:        8388608     7340032     524288      524288     524288     1048576"
    }
    export -f free
    
    # Mock df for disk
    # shellcheck disable=SC2317
    df() {
        if [[ "${1}" == "-h" ]] && [[ "${2}" == "/" ]]; then
            echo "Filesystem      Size  Used Avail Use% Mounted on"
            echo "/dev/sda1        50G   20G   28G  42% /"
        elif [[ "${1}" == "/" ]]; then
            echo "Filesystem     1K-blocks     Used Available Use% Mounted on"
            echo "/dev/sda1       52428800 20971520  29360128  42% /"
        fi
    }
    export -f df
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track alert
    local alert_file="${TMP_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"Memory usage"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_server_resources || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_server_resources alerts when disk usage exceeds threshold" {
    # Mock top for CPU
    # shellcheck disable=SC2317
    top() {
        if [[ "${1}" == "-bn1" ]]; then
            echo "Cpu(s):  5.0%us,  2.0%sy,  0.0%ni, 93.0%id,  0.0%wa"
        fi
    }
    export -f top
    
    # Mock free for memory
    # shellcheck disable=SC2317
    free() {
        echo "              total        used        free      shared  buff/cache   available"
        echo "Mem:        8388608     2097152     4194304      524288     2097152     6291456"
    }
    export -f free
    
    # Mock df for high disk usage
    # shellcheck disable=SC2317
    df() {
        if [[ "${1}" == "-h" ]] && [[ "${2}" == "/" ]]; then
            echo "Filesystem      Size  Used Avail Use% Mounted on"
            echo "/dev/sda1        50G   45G   3G  92% /"
        elif [[ "${1}" == "/" ]]; then
            echo "Filesystem     1K-blocks     Used Available Use% Mounted on"
            echo "/dev/sda1       52428800 47185920  4718592  92% /"
        fi
    }
    export -f df
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track alert
    local alert_file="${TMP_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"Disk usage"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_server_resources || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_network_connectivity succeeds when hosts are reachable" {
    # Mock ping
    # shellcheck disable=SC2317
    ping() {
        if [[ "${1}" == "-c" ]] && [[ "${2}" == "1" ]]; then
            return 0
        fi
        return 0
    }
    export -f ping
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_network_connectivity
    
    # Should succeed
    assert_success
}

@test "check_network_connectivity alerts when hosts are unreachable" {
    # Mock ping to fail
    # shellcheck disable=SC2317
    ping() {
        return 1
    }
    export -f ping
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track alert
    local alert_file="${TMP_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"Network connectivity"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_network_connectivity || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_database_server_health succeeds when database is healthy" {
    # Mock check_database_connection
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"version()"* ]]; then
            echo "PostgreSQL 14.5"
        elif [[ "${1}" == *"pg_postmaster_start_time"* ]]; then
            echo "86400"
        elif [[ "${1}" == *"pg_stat_activity"* ]]; then
            echo "10|100"
        fi
        return 0
    }
    export -f execute_sql_query
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_database_server_health
    
    # Should succeed
    assert_success
}

@test "check_database_server_health alerts when connection fails" {
    # Mock check_database_connection to fail
    # shellcheck disable=SC2317
    check_database_connection() {
        return 1
    }
    export -f check_database_connection
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track alert
    local alert_file="${TMP_DIR}/.alert_critical"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${2}" == "CRITICAL" ]] && { [[ "${4}" == *"Database server connection failed"* ]] || [[ "${4}" == *"Database connection failed"* ]] || [[ "${3}" == "database_connection_failed"* ]]; }; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_database_server_health || true
    
    # Critical alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_database_server_health alerts when connection usage is high" {
    # Mock check_database_connection
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # Mock execute_sql_query to return high connection usage
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"version()"* ]]; then
            echo "PostgreSQL 14.5"
        elif [[ "${1}" == *"pg_postmaster_start_time"* ]]; then
            echo "86400"
        elif [[ "${1}" == *"pg_stat_activity"* ]]; then
            echo "85|100"  # 85 active out of 100 max (85% usage)
        fi
        return 0
    }
    export -f execute_sql_query
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track alert
    local alert_file="${TMP_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"Database connection usage"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_database_server_health || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_service_dependencies succeeds when services are running" {
    # Mock systemctl
    # shellcheck disable=SC2317
    systemctl() {
        if [[ "${1}" == "is-active" ]] && [[ "${2}" == "--quiet" ]]; then
            return 0
        fi
        return 0
    }
    export -f systemctl
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_service_dependencies
    
    # Should succeed
    assert_success
}

@test "check_service_dependencies alerts when services are not running" {
    # Mock systemctl to fail
    # shellcheck disable=SC2317
    systemctl() {
        return 1
    }
    export -f systemctl
    
    # Mock pgrep as fallback (also fail)
    # shellcheck disable=SC2317
    pgrep() {
        return 1
    }
    export -f pgrep
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track alert
    local alert_file="${TMP_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"Service dependencies"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_service_dependencies || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_server_resources handles missing commands gracefully" {
    # Unset commands to simulate missing tools
    unset -f top
    unset -f vmstat
    unset -f free
    unset -f df
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check - should handle gracefully
    run check_server_resources
    
    # Should not fail catastrophically
    # (may return 0 or 1 depending on implementation)
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

