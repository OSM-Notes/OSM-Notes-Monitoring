#!/usr/bin/env bash
#
# Third Unit Tests: ipBlocking.sh
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
    source "${BATS_TEST_DIRNAME}/../../../bin/security/ipBlocking.sh"
    
    init_logging "${TEST_LOG_DIR}/test_ipBlocking_third.log" "test_ipBlocking_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: whitelist_add handles reason parameter
##
@test "whitelist_add handles reason parameter" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*ip_management ]] && [[ "${*}" =~ reason ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run whitelist_add "192.168.1.1" "60" "Test reason"
    assert_success
}

##
# Test: blacklist_add handles reason parameter
##
@test "blacklist_add handles reason parameter" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*ip_management ]] && [[ "${*}" =~ reason ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run blacklist_add "192.168.1.1" "60" "Abuse detected"
    assert_success
}

##
# Test: list_ips handles filtering by list type
##
@test "list_ips handles filtering by list type" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*ip_management ]] && [[ "${*}" =~ whitelist ]]; then
            echo "192.168.1.1|2025-12-29"
            return 0
        fi
        return 1
    }
    export -f psql
    
    run list_ips "whitelist"
    assert_success
}

##
# Test: main handles --reason option
##
@test "main handles --reason option" {
    # Mock whitelist_add
    # shellcheck disable=SC2317
    function whitelist_add() {
        return 0
    }
    export -f whitelist_add
    
    run main "whitelist" "add" "192.168.1.1" "60" "Test reason"
    assert_success
}
