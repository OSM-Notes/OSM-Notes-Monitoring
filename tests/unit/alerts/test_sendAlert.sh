#!/usr/bin/env bash
#
# Unit Tests: Send Alert
# Tests enhanced alert sender functionality
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

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
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ADMIN_EMAIL="test@example.com"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_sendAlert.log"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_FILE}" "test_sendAlert"
    
    # Initialize alerting
    init_alerting
}

@test "sendAlert.sh shows usage with --help" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --help
    assert_success
    assert_output --partial "Enhanced Alert Sender Script"
    assert_output --partial "Usage:"
}

@test "format_html generates HTML for critical alert" {
    run format_html "INGESTION" "critical" "data_quality" "Test message"
    assert_success
    assert_output --partial "<!DOCTYPE html>"
    assert_output --partial "#dc3545"  # Red color for critical
    assert_output --partial "INGESTION"
    assert_output --partial "Test message"
}

@test "format_html generates HTML for warning alert" {
    run format_html "ANALYTICS" "warning" "performance" "Test message"
    assert_success
    assert_output --partial "#ffc107"  # Yellow color for warning
}

@test "format_html generates HTML for info alert" {
    run format_html "WMS" "info" "status" "Test message"
    assert_success
    assert_output --partial "#17a2b8"  # Blue color for info
}

@test "format_html includes metadata when provided" {
    run format_html "INGESTION" "critical" "data_quality" "Test message" '{"key": "value"}'
    assert_success
    assert_output --partial "Metadata:"
    assert_output --partial "key"
}

@test "format_json generates valid JSON" {
    run format_json "INGESTION" "critical" "data_quality" "Test message" '{"key": "value"}'
    assert_success
    assert_output --partial '"component": "INGESTION"'
    assert_output --partial '"alert_level": "critical"'
    assert_output --partial '"alert_type": "data_quality"'
    assert_output --partial '"message": "Test message"'
    assert_output --partial '"metadata": {"key": "value"}'
}

@test "format_json uses null for missing metadata" {
    run format_json "INGESTION" "critical" "data_quality" "Test message"
    assert_success
    assert_output --partial '"metadata": null'
}

@test "enhanced_send_alert validates alert level" {
    run enhanced_send_alert "INGESTION" "critical" "test" "Test message"
    assert_success
    
    run enhanced_send_alert "INGESTION" "invalid" "test" "Test message"
    assert_failure
}

@test "enhanced_send_alert accepts critical level" {
    run enhanced_send_alert "INGESTION" "critical" "test" "Test message"
    assert_success
}

@test "enhanced_send_alert accepts warning level" {
    run enhanced_send_alert "INGESTION" "warning" "test" "Test message"
    assert_success
}

@test "enhanced_send_alert accepts info level" {
    run enhanced_send_alert "INGESTION" "info" "test" "Test message"
    assert_success
}

@test "main requires at least 4 arguments" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" "INGESTION" "critical"
    assert_failure
    assert_output --partial "Missing required arguments"
}

@test "main sends alert with text format" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --no-email "INGESTION" "critical" "test" "Test message"
    assert_success
}

@test "main sends alert with json format" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --no-email --format json "INGESTION" "critical" "test" "Test message"
    assert_success
    assert_output --partial '"component": "INGESTION"'
}

@test "main sends alert with html format" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --no-email --format html "INGESTION" "critical" "test" "Test message"
    assert_success
}

@test "main overrides email recipient" {
    export ADMIN_EMAIL="original@example.com"
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --no-email --email "override@example.com" "INGESTION" "critical" "test" "Test message"
    assert_success
    # Email override is set but email is disabled, so we just verify it doesn't fail
}

@test "main skips email when --no-email is used" {
    export SEND_ALERT_EMAIL="true"
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --no-email "INGESTION" "critical" "test" "Test message"
    assert_success
}

@test "main accepts metadata as 5th argument" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --no-email --format json "INGESTION" "critical" "test" "Test message" '{"key": "value"}'
    assert_success
    assert_output --partial '"key": "value"'
}

@test "main handles --slack flag" {
    export SLACK_ENABLED="false"
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --no-email --slack "INGESTION" "critical" "test" "Test message"
    assert_success
    # Slack force is set but we can't verify it without mocking
}

@test "main handles --config flag" {
    local test_config="${BATS_TEST_DIRNAME}/../../../tmp/test_sendAlert_config.conf"
    echo "TEST_CONFIG_VAR=test_value" > "${test_config}"
    
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --no-email --config "${test_config}" "INGESTION" "critical" "test" "Test message"
    assert_success
    
    rm -f "${test_config}"
}

@test "format_html handles empty metadata" {
    run format_html "INGESTION" "critical" "test" "Test message" ""
    assert_success
    assert_output --partial "<!DOCTYPE html>"
}

@test "format_json handles empty metadata string" {
    run format_json "INGESTION" "critical" "test" "Test message" ""
    assert_success
    assert_output --partial '"metadata": null'
}

@test "format_html handles special characters in message" {
    run format_html "INGESTION" "critical" "test" "Test & <message> with 'quotes'"
    assert_success
    assert_output --partial "Test"
}

@test "format_json handles special characters in message" {
    run format_json "INGESTION" "critical" "test" "Test & <message>"
    assert_success
    assert_output --partial "Test"
}

@test "main handles invalid format gracefully" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/sendAlert.sh" --no-email --format invalid "INGESTION" "critical" "test" "Test message"
    assert_success
    # Should default to text format
}

@test "enhanced_send_alert handles missing metadata" {
    run enhanced_send_alert "INGESTION" "critical" "test" "Test message"
    assert_success
}

@test "format_html includes timestamp" {
    run format_html "INGESTION" "critical" "test" "Test message"
    assert_success
    assert_output --partial "Timestamp"
}
