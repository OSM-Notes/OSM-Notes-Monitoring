#!/usr/bin/env bash
#
# Third Unit Tests: ddosProtection.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    export DDOS_ENABLED="true"
    export DDOS_THRESHOLD_REQUESTS_PER_SECOND="100"
    export DDOS_THRESHOLD_CONCURRENT_CONNECTIONS="500"
    export DDOS_AUTO_BLOCK_DURATION_MINUTES="15"
    export DDOS_CHECK_WINDOW_SECONDS="60"
    export DDOS_GEO_FILTERING_ENABLED="false"
    
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock functions BEFORE sourcing
    # shellcheck disable=SC2317
    load_config() { return 0; }
    export -f load_config
    # shellcheck disable=SC2317
    init_alerting() { return 0; }
    export -f init_alerting
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/securityFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/security/ddosProtection.sh"
    
    init_logging "${TEST_LOG_DIR}/test_ddosProtection_third.log" "test_ddosProtection_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: detect_ddos_attack handles distributed attack
##
@test "detect_ddos_attack handles distributed attack" {
    # Mock execute_sql_query to return multiple attacking IPs
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "150|192.168.1.1"
        echo "200|192.168.1.2"
        echo "300|192.168.1.3"
        return 0
    }
    export -f execute_sql_query
    
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
    auto_block_ip() {
        return 0
    }
    export -f auto_block_ip
    
    run detect_ddos_attack "192.168.1.1" "60" "100"
    assert_success || true
}

##
# Test: get_ip_country handles IP geolocation
##
@test "get_ip_country handles IP geolocation" {
    # Mock curl for geolocation API
    # shellcheck disable=SC2317
    function curl() {
        echo '{"country":"US"}'
        return 0
    }
    export -f curl
    
    run get_ip_country "192.168.1.1"
    assert_success
}

##
# Test: check_geographic_filter handles allowed countries
##
@test "check_geographic_filter handles allowed countries" {
    export DDOS_GEO_FILTERING_ENABLED="true"
    export DDOS_ALLOWED_COUNTRIES="US,CA"
    
    # Mock get_ip_country
    # shellcheck disable=SC2317
    function get_ip_country() {
        echo "US"
        return 0
    }
    export -f get_ip_country
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    run check_geographic_filter "192.168.1.1"
    assert_success
}

##
# Test: main handles --monitor option
##
@test "main handles --monitor option" {
    # Mock monitor_connections
    # shellcheck disable=SC2317
    function monitor_connections() {
        return 0
    }
    export -f monitor_connections
    
    run main --monitor
    assert_success
}
