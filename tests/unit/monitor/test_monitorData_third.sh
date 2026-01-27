#!/usr/bin/env bash
#
# Third Unit Tests: monitorData.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    
    export DATA_ENABLED="true"
    export DATA_QUALITY_THRESHOLD="95"
    export DATA_FRESHNESS_THRESHOLD="3600"
    export DATA_BACKUP_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_backup"
    export DATA_BACKUP_FRESHNESS_THRESHOLD="86400"  # 24 hours
    export DATA_STORAGE_PATH="${BATS_TEST_DIRNAME}/../../tmp/test_storage"
    
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    export PGPASSWORD="test_password"
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorData.sh"
    
    init_logging "${TEST_LOG_DIR}/test_monitorData_third.log" "test_monitorData_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_file_integrity handles valid files
##
@test "check_file_integrity handles valid files" {
    # Create test backup directory
    local test_backup_dir="${BATS_TEST_DIRNAME}/../../tmp/test_backup"
    mkdir -p "${test_backup_dir}"
    # shellcheck disable=SC2030,SC2031
    export DATA_BACKUP_DIR="${test_backup_dir}"
    
    # Create valid backup file
    echo "test backup data" > "${test_backup_dir}/backup.sql"
    
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
    
    run check_file_integrity
    assert_success
    
    # Cleanup
    rm -rf "${test_backup_dir}"
}

##
# Test: check_backup_freshness handles fresh backups
##
@test "check_backup_freshness handles fresh backups" {
    # Create test backup directory with recent backup
    local test_backup_dir="${BATS_TEST_DIRNAME}/../../tmp/test_backup"
    mkdir -p "${test_backup_dir}"
    # shellcheck disable=SC2030,SC2031
    export DATA_BACKUP_DIR="${test_backup_dir}"
    export DATA_BACKUP_FRESHNESS_THRESHOLD="86400"  # 24 hours
    
    # Create recent backup file
    touch "${test_backup_dir}/backup_$(date +%Y%m%d).sql"
    
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
    
    run check_backup_freshness
    assert_success
    
    # Cleanup
    rm -rf "${test_backup_dir}"
}

##
# Test: main handles --check option
##
@test "main handles --check option" {
    # Mock psql to avoid database connection
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    export -f psql
    
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
    
    # Create test backup directory
    local test_backup_dir="${BATS_TEST_DIRNAME}/../../tmp/test_backup"
    mkdir -p "${test_backup_dir}"
    touch "${test_backup_dir}/backup_$(date +%Y%m%d).sql"
    # shellcheck disable=SC2031
    export DATA_BACKUP_DIR="${test_backup_dir}"
    
    # Run script directly with --check option
    run bash "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorData.sh" --check backup_freshness
    assert_success
    
    # Cleanup
    rm -rf "${test_backup_dir}"
}
