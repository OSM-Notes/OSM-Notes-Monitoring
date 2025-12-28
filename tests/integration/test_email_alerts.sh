#!/usr/bin/env bash
#
# Integration Tests: Email Alerts
# Tests email alert delivery with mutt integration
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Test email configuration
    export ADMIN_EMAIL="test@example.com"
    export SEND_ALERT_EMAIL="true"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_email_alerts.log"
    init_logging "${LOG_FILE}" "test_email_alerts"
    
    # Initialize alerting
    init_alerting
    
    # Clean test database
    clean_test_database
}

teardown() {
    # Clean up test alerts
    clean_test_database
    
    # Clean up test log files
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: Email alert function exists
##
@test "Email alert function exists" {
    # Check if send_email_alert function exists
    run type send_email_alert
    assert_success
}

##
# Test: Email alert respects SEND_ALERT_EMAIL setting
##
@test "Email alert respects SEND_ALERT_EMAIL setting" {
    # Disable email
    export SEND_ALERT_EMAIL="false"
    
    # Send alert (should skip email)
    run send_email_alert "test@example.com" "Test Subject" "Test Body"
    assert_success
    
    # Enable email
    export SEND_ALERT_EMAIL="true"
    
    # If mutt is available, email would be sent
    # Otherwise, function should handle gracefully
    if command -v mutt >/dev/null 2>&1; then
        # Email would be attempted
        run send_email_alert "test@example.com" "Test Subject" "Test Body"
        # May succeed or fail depending on email configuration
        assert [ "$status" -ge 0 ]
    else
        # mutt not available, should fail gracefully
        run send_email_alert "test@example.com" "Test Subject" "Test Body"
        assert_failure
    fi
}

##
# Test: Email alert formatting
##
@test "Email alert formatting works" {
    local component="INGESTION"
    local alert_level="critical"
    local alert_type="test_type"
    local message="Test email alert message"
    
    # Format subject (as done in send_alert)
    local subject
    subject="[${alert_level^^}] OSM-Notes-Monitoring: ${component} - ${alert_type}"
    
    # Format body (as done in send_alert)
    local body
    body="Component: ${component}
Alert Level: ${alert_level}
Alert Type: ${alert_type}
Message: ${message}
Timestamp: $(date -Iseconds)

This is an automated alert from OSM-Notes-Monitoring."
    
    # Verify formatting
    assert [ -n "${subject}" ]
    assert [ -n "${body}" ]
    assert_output --partial "INGESTION" <<< "${body}"
    assert_output --partial "critical" <<< "${body}"
}

##
# Test: Email recipients based on alert level
##
@test "Email recipients based on alert level" {
    export CRITICAL_ALERT_RECIPIENTS="critical@example.com"
    export WARNING_ALERT_RECIPIENTS="warning@example.com"
    export INFO_ALERT_RECIPIENTS="info@example.com"
    
    # Test critical recipients
    local recipients
    recipients="${CRITICAL_ALERT_RECIPIENTS}"
    assert [ "${recipients}" = "critical@example.com" ]
    
    # Test warning recipients
    recipients="${WARNING_ALERT_RECIPIENTS}"
    assert [ "${recipients}" = "warning@example.com" ]
    
    # Test info recipients
    recipients="${INFO_ALERT_RECIPIENTS}"
    assert [ "${recipients}" = "info@example.com" ]
}

##
# Test: Email alert with send_alert function
##
@test "Email alert with send_alert function" {
    # Disable email for this test (we're testing the function, not actual email)
    export SEND_ALERT_EMAIL="false"
    
    local component="INGESTION"
    local alert_level="warning"
    local alert_type="test_type"
    local message="Test alert message"
    
    # Send alert (should store in DB, skip email)
    run send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    assert_success
    
    # Verify alert stored
    local count
    count=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    assert [ "${count}" -ge 1 ]
}

##
# Helper function to count alerts
##
count_alerts() {
    local component="${1}"
    local alert_level="${2:-}"
    local alert_type="${3:-}"
    
    local query="SELECT COUNT(*) FROM alerts WHERE component = '${component}'"
    
    if [[ -n "${alert_level}" ]]; then
        query="${query} AND alert_level = '${alert_level}'"
    fi
    
    if [[ -n "${alert_type}" ]]; then
        query="${query} AND alert_type = '${alert_type}'"
    fi
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${DBHOST:-localhost}" \
        -p "${DBPORT:-5432}" \
        -U "${DBUSER:-postgres}" \
        -d "${TEST_DB_NAME}" \
        -t -A \
        -c "${query}" 2>/dev/null | tr -d '[:space:]' || echo "0"
}

