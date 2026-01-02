#!/usr/bin/env bash
#
# Unit Tests: monitorData.sh
# Tests data monitoring check functions
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_BACKUP_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_backups"
TEST_REPO_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_repo"
TEST_STORAGE_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_storage"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
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
    
    # Disable alerts for unit tests
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Mock database functions to avoid real DB calls
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock psql FIRST to avoid password prompts (needed by execute_sql_query)
    # shellcheck disable=SC2317
    psql() {
        return 0
    }
    export -f psql
    
    # Mock database functions to avoid password prompts
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
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
    
    # Mock record_metric to avoid database calls (called by monitorData.sh)
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Source libraries (after mocks are defined)
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
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test.log" "test_monitorData"
    
    # Initialize alerting
    init_alerting
    
    # Re-export mocks after sourcing (to ensure they override library functions)
    export -f psql
    export -f check_database_connection
    export -f execute_sql_query
    export -f store_alert
    export -f record_metric
    
    # Source monitorData.sh functions
    # Set component name BEFORE sourcing (to allow override)
    export TEST_MODE=true
    export COMPONENT="DATA"
    
    # We'll source it but need to handle the main execution
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorData.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_BACKUP_DIR}"
    rm -rf "${TEST_REPO_DIR}"
    rm -rf "${TEST_STORAGE_DIR}"
    rm -rf "${TEST_LOG_DIR}"
    rm -f "${TMP_DIR}/.alert_sent"
    rm -f "${TMP_DIR}/.alert_critical"
}

##
# Helper: Create test backup file
##
create_test_backup() {
    local backup_name="${1}"
    local age_seconds="${2:-0}"
    
    local backup_path="${TEST_BACKUP_DIR}/${backup_name}"
    echo "Test backup content" > "${backup_path}"
    
    if [[ ${age_seconds} -gt 0 ]]; then
        local timestamp
        timestamp=$(date -d "${age_seconds} seconds ago" +%s 2>/dev/null || date -v-"${age_seconds}"S +%s 2>/dev/null || echo "")
        if [[ -n "${timestamp}" ]]; then
            touch -t "$(date -d "@${timestamp}" +%Y%m%d%H%M.%S 2>/dev/null || date -r "${timestamp}" +%Y%m%d%H%M.%S 2>/dev/null || echo "")" "${backup_path}" 2>/dev/null || true
        fi
    fi
}

@test "check_backup_freshness succeeds when backups are fresh" {
    # Create fresh backup files
    create_test_backup "backup_$(date +%Y%m%d).sql" 0
    create_test_backup "backup_$(date +%Y%m%d).dump" 3600
    
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
    run check_backup_freshness
    
    # Should succeed
    assert_success
}

@test "check_backup_freshness alerts when backup directory does not exist" {
    # Set non-existent directory
    export DATA_BACKUP_DIR="/nonexistent/directory"
    
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
        if [[ "${4}" == *"Backup directory does not exist"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_backup_freshness || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_backup_freshness alerts when no backups found" {
    # Empty backup directory
    if [[ -d "${TEST_BACKUP_DIR}" ]]; then
        find "${TEST_BACKUP_DIR}" -mindepth 1 -delete 2>/dev/null || true
    fi
    
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
        if [[ "${4}" == *"No backup files found"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_backup_freshness || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_backup_freshness alerts when newest backup is too old" {
    # Create old backup files (older than threshold)
    create_test_backup "backup_old.sql" 172800  # 2 days old
    
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
        if [[ "${4}" == *"Newest backup is"* ]] && [[ "${4}" == *"old"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_backup_freshness || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_repository_sync_status succeeds when repository is synced" {
    # Initialize git repository
    if command -v git > /dev/null 2>&1; then
        cd "${TEST_REPO_DIR}" || return 1
        git init > /dev/null 2>&1
        git config user.email "test@example.com" > /dev/null 2>&1
        git config user.name "Test User" > /dev/null 2>&1
        echo "test" > test.txt
        git add test.txt > /dev/null 2>&1
        git commit -m "Initial commit" > /dev/null 2>&1
        cd - > /dev/null || true
    else
        skip "git not available"
    fi
    
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
    run check_repository_sync_status
    
    # Should succeed (or skip if git not available)
    if ! command -v git > /dev/null 2>&1; then
        skip "git not available"
    fi
    assert_success
}

@test "check_repository_sync_status skips when repository path not configured" {
    # Unset repository path
    export DATA_REPO_PATH=""
    
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
    run check_repository_sync_status
    
    # Should succeed (skip)
    assert_success
}

@test "check_repository_sync_status skips when directory is not a git repository" {
    # Create non-git directory
    echo "not a git repo" > "${TEST_REPO_DIR}/file.txt"
    
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
    run check_repository_sync_status
    
    # Should succeed (skip)
    assert_success
}

@test "check_file_integrity succeeds when files are valid" {
    # Create valid backup files
    echo "PostgreSQL dump" > "${TEST_BACKUP_DIR}/backup.sql"
    echo "Test content" | gzip > "${TEST_BACKUP_DIR}/backup.tar.gz" 2>/dev/null || echo "compressed" > "${TEST_BACKUP_DIR}/backup.tar.gz"
    
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
    run check_file_integrity
    
    # Should succeed
    assert_success
}

@test "check_file_integrity alerts when files are not readable" {
    # Create unreadable file
    echo "test" > "${TEST_BACKUP_DIR}/backup.sql"
    chmod 000 "${TEST_BACKUP_DIR}/backup.sql"
    
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
        if [[ "${4}" == *"File integrity check found"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_file_integrity || true
    
    # Restore permissions for cleanup
    chmod 644 "${TEST_BACKUP_DIR}/backup.sql" 2>/dev/null || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_file_integrity alerts when files are empty" {
    # Create empty file
    touch "${TEST_BACKUP_DIR}/backup.sql"
    
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
        if [[ "${4}" == *"File integrity check found"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_file_integrity || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_file_integrity alerts when compressed files are corrupted" {
    # Create corrupted compressed file (invalid gzip)
    echo "not a valid gzip file" > "${TEST_BACKUP_DIR}/backup.tar.gz"
    
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
        if [[ "${4}" == *"File integrity check found"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check (may skip if gzip not available)
    if command -v gzip > /dev/null 2>&1; then
        run check_file_integrity || true
        
        # Alert should have been sent
        assert_file_exists "${alert_file}"
    else
        skip "gzip not available"
    fi
}

@test "check_storage_availability succeeds when storage is available" {
    # Ensure storage directory exists and is writable
    mkdir -p "${TEST_STORAGE_DIR}"
    chmod 755 "${TEST_STORAGE_DIR}"
    
    # Mock df for disk usage
    # shellcheck disable=SC2317
    df() {
        if [[ "${1}" == "-h" ]] && [[ "${2}" == "${TEST_STORAGE_DIR}" ]]; then
            echo "Filesystem      Size  Used Avail Use% Mounted on"
            echo "/dev/sda1        50G   20G   28G  42% /"
        elif [[ "${1}" == "${TEST_STORAGE_DIR}" ]]; then
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
    run check_storage_availability
    
    # Should succeed
    assert_success
}

@test "check_storage_availability alerts when disk usage exceeds threshold" {
    # Ensure storage directory exists
    mkdir -p "${TEST_STORAGE_DIR}"
    
    # Mock df for high disk usage
    # shellcheck disable=SC2317
    df() {
        if [[ "${1}" == "-h" ]] && [[ "${2}" == "${TEST_STORAGE_DIR}" ]]; then
            echo "Filesystem      Size  Used Avail Use% Mounted on"
            echo "/dev/sda1        50G   45G   3G  92% /"
        elif [[ "${1}" == "${TEST_STORAGE_DIR}" ]]; then
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
    run check_storage_availability || true
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_storage_availability alerts CRITICAL when disk usage exceeds 95%" {
    # Ensure storage directory exists
    mkdir -p "${TEST_STORAGE_DIR}"
    
    # Mock df for very high disk usage
    # shellcheck disable=SC2317
    df() {
        if [[ "${1}" == "-h" ]] && [[ "${2}" == "${TEST_STORAGE_DIR}" ]]; then
            echo "Filesystem      Size  Used Avail Use% Mounted on"
            echo "/dev/sda1        50G   48G   1G  96% /"
        elif [[ "${1}" == "${TEST_STORAGE_DIR}" ]]; then
            echo "Filesystem     1K-blocks     Used Available Use% Mounted on"
            echo "/dev/sda1       52428800 50331648  2097152  96% /"
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
        if [[ "${2}" == "CRITICAL" ]] && [[ "${4}" == *"Disk usage"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_storage_availability || true
    
    # Critical alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_storage_availability alerts CRITICAL when storage is not writable" {
    # Create non-writable directory
    mkdir -p "${TEST_STORAGE_DIR}"
    chmod 555 "${TEST_STORAGE_DIR}"
    
    # Mock df for disk usage
    # shellcheck disable=SC2317
    df() {
        if [[ "${1}" == "-h" ]] && [[ "${2}" == "${TEST_STORAGE_DIR}" ]]; then
            echo "Filesystem      Size  Used Avail Use% Mounted on"
            echo "/dev/sda1        50G   20G   28G  42% /"
        elif [[ "${1}" == "${TEST_STORAGE_DIR}" ]]; then
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
        if [[ "${2}" == "CRITICAL" ]] && [[ "${4}" == *"not writable"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_storage_availability || true
    
    # Restore permissions for cleanup
    chmod 755 "${TEST_STORAGE_DIR}" 2>/dev/null || true
    
    # Critical alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_storage_availability skips when storage path not configured" {
    # Unset storage path
    export DATA_STORAGE_PATH=""
    
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
    run check_storage_availability
    
    # Should succeed (skip)
    assert_success
}

@test "check_backup_freshness records metrics correctly" {
    # Create backup files
    create_test_backup "backup1.sql" 3600
    create_test_backup "backup2.dump" 7200
    
    # Use a file to track metrics count (can be modified from mock function)
    local metrics_file="${TMP_DIR}/.metrics_count"
    echo "0" > "${metrics_file}"
    
    # Unset the function first to ensure our mock is used
    unset -f record_metric 2>/dev/null || true
    
    # Mock record_metric to count calls
    # record_metric signature: component metric_name metric_value metadata
    # So ${1} = component, ${2} = metric_name, ${3} = metric_value, ${4} = metadata
    # shellcheck disable=SC2317
    record_metric() {
        # Check if this is one of the backup metrics we're tracking
        if [[ "${2}" == "backup_count" ]] || [[ "${2}" == "backup_newest_age_seconds" ]] || [[ "${2}" == "backup_oldest_age_seconds" ]]; then
            local current_count
            current_count=$(cat "${metrics_file}" 2>/dev/null || echo "0")
            echo $((current_count + 1)) > "${metrics_file}"
        fi
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
    run check_backup_freshness
    
    # Should have recorded metrics
    local metrics_recorded
    metrics_recorded=$(cat "${metrics_file}" 2>/dev/null || echo "0")
    assert [ "${metrics_recorded}" -ge 3 ]
}

