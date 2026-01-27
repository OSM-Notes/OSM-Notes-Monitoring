#!/usr/bin/env bash
#
# Third Unit Tests: monitorWMS.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    
    export WMS_ENABLED="true"
    export WMS_AVAILABILITY_THRESHOLD="95"
    export WMS_RESPONSE_TIME_THRESHOLD="1000"
    export WMS_BASE_URL="http://localhost:8080/geoserver"
    export WMS_HEALTH_CHECK_URL="${WMS_BASE_URL}/wms"
    export WMS_CHECK_TIMEOUT="30"
    
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
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorWMS.sh"
    
    init_logging "${TEST_LOG_DIR}/test_monitorWMS_third.log" "test_monitorWMS_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_wms_service_availability handles 100% availability
##
@test "check_wms_service_availability handles 100% availability" {
    # Create mock curl executable so command -v finds it
    local mock_curl_dir="${BATS_TEST_DIRNAME}/../../tmp/bin"
    mkdir -p "${mock_curl_dir}"
    local mock_curl="${mock_curl_dir}/curl"
    cat > "${mock_curl}" << 'EOF'
#!/bin/bash
# Handle curl arguments: -s -o /dev/null -w "%{http_code}" --max-time ... --connect-timeout ... URL
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w)
            shift
            if [[ "$1" == "%{http_code}" ]]; then
                echo "200"
            fi
            ;;
        -s|-o|--max-time|--connect-timeout)
            shift  # Skip argument value
            ;;
        *)
            # URL or other args
            ;;
    esac
    shift
done
exit 0
EOF
    chmod +x "${mock_curl}"
    # shellcheck disable=SC2030,SC2031
    export PATH="${mock_curl_dir}:${PATH}"
    
    # Mock date to simulate timing
    # shellcheck disable=SC2317
    function date() {
        if [[ "${1}" == "+%s%N" ]]; then
            # shellcheck disable=SC2030,SC2031
            if [[ -z "${date_counter:-}" ]]; then
                date_counter=0
            fi
            if [[ ${date_counter} -eq 0 ]]; then
                echo "1000000000000"  # Start time
                date_counter=1
            else
                echo "1000000050000"  # End time (50ms later)
                date_counter=0
            fi
            return 0
        fi
        command date "$@"
    }
    export -f date
    
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
    log_error() {
        return 0
    }
    export -f log_error
    
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
    
    run check_wms_service_availability
    assert_success
    
    # Cleanup
    rm -rf "${mock_curl_dir}"
}

##
# Test: check_response_time handles very fast response
##
@test "check_response_time handles very fast response" {
    # Create mock curl executable so command -v finds it
    local mock_curl_dir="${BATS_TEST_DIRNAME}/../../tmp/bin"
    mkdir -p "${mock_curl_dir}"
    local mock_curl="${mock_curl_dir}/curl"
    cat > "${mock_curl}" << 'EOF'
#!/bin/bash
# Handle curl arguments: -s -o /dev/null -w "%{http_code}" --max-time ... --connect-timeout ... URL
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w)
            shift
            if [[ "$1" == "%{http_code}" ]]; then
                echo "200"
            fi
            ;;
        -s|-o|--max-time|--connect-timeout)
            shift  # Skip argument value
            ;;
        *)
            # URL or other args
            ;;
    esac
    shift
done
exit 0
EOF
    chmod +x "${mock_curl}"
    # shellcheck disable=SC2031
    export PATH="${mock_curl_dir}:${PATH}"
    
    # Mock date to simulate timing
    # shellcheck disable=SC2317
    function date() {
        if [[ "${1}" == "+%s%N" ]]; then
            # Return timestamps that simulate 50ms difference
            # shellcheck disable=SC2031
            if [[ -z "${date_counter:-}" ]]; then
                date_counter=0
            fi
            if [[ ${date_counter} -eq 0 ]]; then
                echo "1000000000000"  # Start time
                date_counter=1
            else
                echo "1000000050000"  # End time (50ms later)
                date_counter=0
            fi
            return 0
        fi
        command date "$@"
    }
    export -f date
    
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
    log_info() {
        return 0
    }
    export -f log_info
    
    # shellcheck disable=SC2317
    log_warning() {
        return 0
    }
    export -f log_warning
    
    export WMS_CHECK_TIMEOUT="30"
    
    run check_response_time
    assert_success
    
    # Cleanup
    rm -rf "${mock_curl_dir}"
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
    
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        echo "200"
        return 0
    }
    export -f curl
    
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
    
    # Run script directly with --check option
    run bash "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorWMS.sh" --check availability
    assert_success
}
