#!/usr/bin/env bash
#
# Third Unit Tests: sendAlert.sh
# Third test file to reach 80% coverage
#

# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Not following source files is expected in BATS tests

export TEST_COMPONENT="ALERTS"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    init_logging "${LOG_DIR}/test_sendAlert_third.log" "test_sendAlert_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: format_html handles all alert levels with colors
##
@test "format_html handles all alert levels with colors" {
    run format_html "TEST_COMPONENT" "critical" "test" "Message"
    assert_success
    assert_output --partial "[CRITICAL]"
    
    run format_html "TEST_COMPONENT" "warning" "test" "Message"
    assert_success
    assert_output --partial "[WARNING]"
    
    run format_html "TEST_COMPONENT" "info" "test" "Message"
    assert_success
    assert_output --partial "[INFO]"
}

##
# Test: format_json handles all fields
##
@test "format_json handles all fields" {
    run format_json "TEST_COMPONENT" "critical" "test" "Message" '{"key":"value"}'
    assert_success
    assert_output --partial "TEST_COMPONENT"
    assert_output --partial "critical"
    assert_output --partial "test"
    assert_output --partial "Message"
}

##
# Test: enhanced_send_alert handles all notification channels
##
@test "enhanced_send_alert handles all notification channels" {
    export SEND_ALERT_EMAIL="true"
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    export ADMIN_EMAIL="test@example.com"
    
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
    
    # shellcheck disable=SC2317
    function store_alert() {
        return 0
    }
    export -f store_alert
    
    run enhanced_send_alert "TEST_COMPONENT" "critical" "test" "Message"
    assert_success
}

##
# Test: main handles --format option
##
@test "main handles --format option" {
    # Mock enhanced_send_alert
    # shellcheck disable=SC2317
    function enhanced_send_alert() {
        return 0
    }
    export -f enhanced_send_alert
    
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --format json "TEST_COMPONENT" "critical" "test" "Message"
    assert_success
}

##
# Test: main handles --slack option
##
@test "main handles --slack option" {
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    
    # Mock enhanced_send_alert
    # shellcheck disable=SC2317
    function enhanced_send_alert() {
        return 0
    }
    export -f enhanced_send_alert
    
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --slack "TEST_COMPONENT" "critical" "test" "Message"
    assert_success
}
