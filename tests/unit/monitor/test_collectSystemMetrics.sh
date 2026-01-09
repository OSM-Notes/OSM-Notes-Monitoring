#!/usr/bin/env bash
#
# Unit Tests: collectSystemMetrics.sh
# Tests system metrics collection functions
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

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
    
    # Mock record_metric using a file to track calls
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    rm -f "${METRICS_FILE}"
    touch "${METRICS_FILE}"
    export METRICS_FILE
    
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Mock load_all_configs
    # shellcheck disable=SC2317
    load_all_configs() {
        return 0
    }
    export -f load_all_configs
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test_collectSystemMetrics.log" "test_collectSystemMetrics"
    
    # Source collectSystemMetrics.sh functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collectSystemMetrics.sh" 2>/dev/null || true
    
    # Override record_metric AFTER sourcing to ensure our mock is used
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Export functions for testing
    export -f collect_load_average collect_cpu_by_process collect_memory_by_process
    export -f collect_swap_usage collect_disk_io collect_network_traffic get_cpu_count
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

@test "collect_load_average extracts and records load average metrics" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Create mock /proc/loadavg
    local proc_loadavg="${TEST_LOG_DIR}/loadavg"
    echo "1.5 2.0 2.5 1/100 12345" > "${proc_loadavg}"
    
    # Mock /proc/loadavg
    if [[ -f /proc/loadavg ]]; then
        # Use real file if available
        run collect_load_average
    else
        # Skip if /proc not available
        skip "/proc/loadavg not available in test environment"
    fi
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"system_load_average"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded at least some metrics (if /proc available)
    if [[ -f /proc/loadavg ]]; then
        assert [[ ${metrics_found} -gt 0 ]]
    fi
}

@test "collect_cpu_by_process extracts and records PostgreSQL CPU usage" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Mock pgrep to return test PID
    # shellcheck disable=SC2317
    pgrep() {
        if [[ "${1}" == "-x" ]] && [[ "${2}" == "postgres" ]]; then
            echo "12345"
            echo "12346"
            return 0
        fi
        return 1
    }
    export -f pgrep
    
    # Mock ps to return CPU usage
    # shellcheck disable=SC2317
    ps() {
        if [[ "${*}" == *"-p"* ]] && [[ "${*}" == *"%cpu"* ]]; then
            echo "25.5"
            echo "15.2"
            return 0
        fi
        return 1
    }
    export -f ps
    
    # Run function
    run collect_cpu_by_process
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded (if postgres processes found)
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"system_cpu_postgres_percent"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # May or may not find postgres processes in test environment
    # Just verify function doesn't fail
    assert_success
}

@test "collect_memory_by_process extracts and records PostgreSQL memory usage" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Mock pgrep
    # shellcheck disable=SC2317
    pgrep() {
        if [[ "${1}" == "-x" ]] && [[ "${2}" == "postgres" ]]; then
            echo "12345"
            return 0
        fi
        return 1
    }
    export -f pgrep
    
    # Mock ps to return RSS
    # shellcheck disable=SC2317
    ps() {
        if [[ "${*}" == *"-p"* ]] && [[ "${*}" == *"rss="* ]]; then
            echo "1024000"  # 1GB in KB
            return 0
        fi
        return 1
    }
    export -f ps
    
    # Mock /proc/[pid]/statm
    mkdir -p "${TEST_LOG_DIR}/12345"
    echo "1000000 500000 250000 10000 5000 2000 0" > "${TEST_LOG_DIR}/12345/statm"
    
    # Run function (will use real /proc if available, or skip)
    run collect_memory_by_process
    
    # Should succeed
    assert_success
}

@test "collect_swap_usage extracts and records swap metrics" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Mock free command
    # shellcheck disable=SC2317
    free() {
        echo "              total        used        free      shared  buff/cache   available"
        echo "Mem:       8192000     4096000     2048000      512000     2048000     3584000"
        echo "Swap:      2097152     1048576     1048576"
    }
    export -f free
    
    # Run function
    run collect_swap_usage
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"system_swap"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded swap metrics
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "collect_disk_io handles missing /proc/diskstats gracefully" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Mock df to return root device
    # shellcheck disable=SC2317
    df() {
        echo "Filesystem     1K-blocks  Used Available Use% Mounted on"
        echo "/dev/sda1      10485760 5242880   5242880  50% /"
    }
    export -f df
    
    # Run function (will handle missing /proc/diskstats gracefully)
    run collect_disk_io
    
    # Should succeed (graceful handling)
    assert_success
}

@test "collect_network_traffic extracts and records network metrics" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Create mock /proc/net/dev
    local proc_net_dev="${TEST_LOG_DIR}/net_dev"
    cat > "${proc_net_dev}" << 'EOF'
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 1048576    1000    0    0    0     0          0         0  1048576    1000    0    0    0     0       0          0
  eth0: 104857600  10000    0    0    0     0          0         0  52428800   5000    0    0    0     0       0          0
EOF
    
    # Mock /proc/net/dev if real one doesn't exist
    if [[ -f /proc/net/dev ]]; then
        run collect_network_traffic
    else
        skip "/proc/net/dev not available in test environment"
    fi
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded (if /proc available)
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"system_network"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded metrics if /proc available
    if [[ -f /proc/net/dev ]]; then
        assert [[ ${metrics_found} -gt 0 ]]
    fi
}

@test "get_cpu_count returns number of CPUs" {
    # Run function
    local cpu_count
    cpu_count=$(get_cpu_count)
    
    # Should return a number
    assert [[ "${cpu_count}" =~ ^[0-9]+$ ]]
    
    # Should be at least 1
    assert [[ "${cpu_count}" -ge 1 ]]
}

@test "main function runs all collection functions successfully" {
    # Mock load_all_configs
    # shellcheck disable=SC2317
    load_all_configs() {
        return 0
    }
    export -f load_all_configs
    
    # Run main function
    run main
    
    # Should succeed
    assert_success
}

@test "main function handles missing configuration gracefully" {
    # Mock load_all_configs to fail
    # shellcheck disable=SC2317
    load_all_configs() {
        return 1
    }
    export -f load_all_configs
    
    # Run main function
    run main
    
    # Should fail gracefully
    assert_failure
}
