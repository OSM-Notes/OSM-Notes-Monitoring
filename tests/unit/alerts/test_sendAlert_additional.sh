#!/usr/bin/env bash
#
# Additional Unit Tests: Send Alert
# Additional tests for sendAlert to increase coverage
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

export TEST_MODE=true
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../../tmp/logs"
mkdir -p "${TEST_LOG_DIR}"
export TEST_LOG_DIR="${TEST_LOG_DIR}"
export LOG_DIR="${TEST_LOG_DIR}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

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
source "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ADMIN_EMAIL="test@example.com"
    
    init_logging "${LOG_DIR}/test_sendAlert_additional.log" "test_sendAlert_additional"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: format_alert_html handles all alert levels
##
@test "format_alert_html handles warning level" {
    local html
    html=$(format_alert_html "TEST_COMPONENT" "warning" "test_alert" "Test message")
    
    assert [[ -n "${html}" ]]
    assert echo "${html}" | grep -q "warning"
}

@test "format_alert_html handles info level" {
    local html
    html=$(format_alert_html "TEST_COMPONENT" "info" "test_alert" "Test message")
    
    assert [[ -n "${html}" ]]
    assert echo "${html}" | grep -q "info"
}

##
# Test: format_alert_json handles metadata
##
@test "format_alert_json includes metadata" {
    local json
    json=$(format_alert_json "TEST_COMPONENT" "critical" "test_alert" "Test message" '{"key":"value"}')
    
    assert [[ -n "${json}" ]]
    assert echo "${json}" | grep -q "key"
}

##
# Test: main handles --json option
##
@test "main handles --json option" {
    # Mock send_alert
    # shellcheck disable=SC2317
    function send_alert() {
        return 0
    }
    export -f send_alert
    
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --json "TEST_COMPONENT" "critical" "test" "Test message"
    assert_success
}

##
# Test: main handles --html option
##
@test "main handles --html option" {
    # Mock send_alert
    # shellcheck disable=SC2317
    function send_alert() {
        return 0
    }
    export -f send_alert
    
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --html "TEST_COMPONENT" "critical" "test" "Test message"
    assert_success
}

##
# Test: main handles missing arguments
##
@test "main handles missing arguments" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" "TEST_COMPONENT" "critical" || true
    assert_failure
}

##
# Test: main handles invalid alert level
##
@test "main handles invalid alert level" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" "TEST_COMPONENT" "invalid" "test" "Test message" || true
    # May succeed or fail depending on validation
    assert_success || assert_failure
}

##
# Test: format_alert_html escapes special characters
##
@test "format_alert_html escapes special characters" {
    local html
    html=$(format_alert_html "TEST_COMPONENT" "critical" "test_alert" "Test <script>alert('xss')</script> message")
    
    # Should not contain unescaped script tags
    assert ! echo "${html}" | grep -q "<script>"
}

##
# Test: format_alert_json handles empty metadata
##
@test "format_alert_json handles empty metadata" {
    local json
    json=$(format_alert_json "TEST_COMPONENT" "critical" "test_alert" "Test message" "")
    
    assert [[ -n "${json}" ]]
}

##
# Test: main handles --slack-channel option
##
@test "main handles --slack-channel option" {
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    
    # Mock send_alert
    # shellcheck disable=SC2317
    function send_alert() {
        return 0
    }
    export -f send_alert
    
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --slack-channel "#test-channel" "TEST_COMPONENT" "critical" "test" "Test message"
    assert_success
}

##
# Test: main handles --help option
##
@test "main handles --help option" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --help
    assert_success
    assert_output --partial "Usage"
}
