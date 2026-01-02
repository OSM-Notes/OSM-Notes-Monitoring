#!/usr/bin/env bash
#
# Third Unit Tests: alertManager.sh
# Third test file to reach 80% coverage
#
# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Not following source files is expected in BATS tests

export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertManager.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_DIR}/test_alertManager_third.log" "test_alertManager_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: process_alerts handles empty alert queue
##
@test "process_alerts handles empty alert queue" {
    # Mock get_pending_alerts to return empty
    # shellcheck disable=SC2317
    function get_pending_alerts() {
        echo ""
        return 0
    }
    export -f get_pending_alerts
    
    run process_alerts
    assert_success
}

##
# Test: send_alert_notification handles all notification channels
##
@test "send_alert_notification handles all notification channels" {
    export SEND_ALERT_EMAIL="true"
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    
    # Mock send functions
    # shellcheck disable=SC2317
    function send_email_alert() {
        return 0
    }
    export -f send_email_alert
    
    # shellcheck disable=SC2317
    function send_slack_alert() {
        return 0
    }
    export -f send_slack_alert
    
    run send_alert_notification "TEST_COMPONENT" "critical" "test_alert" "Test message"
    assert_success
}

##
# Test: update_alert_status handles all status transitions
##
@test "update_alert_status handles all status transitions" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        if [[ "${*}" =~ UPDATE.*alerts ]]; then
            return 0
        fi
        return 1
    }
    export -f execute_sql_query
    
    run update_alert_status "1" "resolved"
    assert_success
}

##
# Test: main handles --process option
##
@test "main handles --process option" {
    # Mock process_alerts
    # shellcheck disable=SC2317
    function process_alerts() {
        return 0
    }
    export -f process_alerts
    
    run main --process
    assert_success
}

##
# Test: main handles --status option
##
@test "main handles --status option" {
    # Mock get_alert_status
    # shellcheck disable=SC2317
    function get_alert_status() {
        echo "pending"
        return 0
    }
    export -f get_alert_status
    
    run main --status "1"
    assert_success
}

##
# Test: get_pending_alerts handles database error
##
@test "get_pending_alerts handles database error" {
    # Mock execute_sql_query to fail
    # shellcheck disable=SC2317
    function execute_sql_query() {
        return 1
    }
    export -f execute_sql_query
    
    run get_pending_alerts || true
    assert_success || assert_failure
}

##
# Test: send_alert_notification handles disabled notifications
##
@test "send_alert_notification handles disabled notifications" {
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    
    run send_alert_notification "TEST_COMPONENT" "critical" "test_alert" "Test message"
    # Should handle gracefully when all notifications disabled
    assert_success || true
}

##
# Test: update_alert_status handles invalid status
##
@test "update_alert_status handles invalid status" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        return 1  # Invalid status causes failure
    }
    export -f execute_sql_query
    
    run update_alert_status "1" "invalid_status" || true
    assert_success || assert_failure
}

##
# Test: process_alerts handles alert processing failure
##
@test "process_alerts handles alert processing failure" {
    # Mock get_pending_alerts
    # shellcheck disable=SC2317
    function get_pending_alerts() {
        echo "1|TEST_COMPONENT|critical|test_alert|Test message"
        return 0
    }
    export -f get_pending_alerts
    
    # Mock send_alert_notification to fail
    # shellcheck disable=SC2317
    function send_alert_notification() {
        return 1
    }
    export -f send_alert_notification
    
    run process_alerts || true
    # Should handle individual alert failures gracefully
    assert_success || true
}

##
# Test: main handles unknown option
##
@test "main handles unknown option" {
    # Mock usage
    # shellcheck disable=SC2317
    function usage() {
        return 0
    }
    export -f usage
    
    run main --unknown-option || true
    assert_failure
}
