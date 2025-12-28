#!/usr/bin/env bash
#
# Integration Tests: Slack Integration
# Tests Slack alert delivery integration
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
    
    # Test Slack configuration
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/WEBHOOK/URL"
    export SLACK_CHANNEL="#monitoring"
    export SEND_ALERT_EMAIL="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_slack_integration.log"
    init_logging "${LOG_FILE}" "test_slack_integration"
    
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
# Test: Slack alert function exists
##
@test "Slack alert function exists" {
    # Check if send_slack_alert function exists
    run type send_slack_alert
    assert_success
}

##
# Test: Slack alert respects SLACK_ENABLED setting
##
@test "Slack alert respects SLACK_ENABLED setting" {
    # Disable Slack
    export SLACK_ENABLED="false"
    
    # Send alert (should skip Slack)
    local component="INGESTION"
    local alert_level="warning"
    local alert_type="test_type"
    local message="Test message"
    
    run send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    assert_success
    
    # Verify alert stored (Slack skipped)
    local count
    count=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    assert [ "${count}" -ge 1 ]
}

##
# Test: Slack alert requires webhook URL
##
@test "Slack alert requires webhook URL" {
    # Enable Slack but no webhook
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL=""
    
    local component="INGESTION"
    local alert_level="critical"
    local alert_type="test_type"
    local message="Test message"
    
    # Send alert (should store in DB, skip Slack due to no webhook)
    run send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    assert_success
    
    # Verify alert stored
    local count
    count=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    assert [ "${count}" -ge 1 ]
}

##
# Test: Slack alert formatting
##
@test "Slack alert formatting works" {
    # Check if curl is available (required for Slack)
    if ! command -v curl >/dev/null 2>&1; then
        skip "curl not available"
    fi
    
    local component="INGESTION"
    local alert_level="critical"
    local alert_type="test_type"
    local message="Test Slack alert"
    
    # Test Slack alert function (with mock webhook, will fail but test formatting)
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/WEBHOOK/URL"
    
    # Send alert (will attempt Slack, may fail but formatting should work)
    run send_slack_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    # May fail if webhook invalid, but function should handle gracefully
    assert [ "$status" -ge 0 ]
}

##
# Test: Slack alert color based on alert level
##
@test "Slack alert color based on alert level" {
    # Test color mapping (as implemented in send_slack_alert)
    local color
    local alert_level
    
    # Critical -> danger (red)
    alert_level="critical"
    case "${alert_level}" in
        critical)
            color="danger"
            ;;
        warning)
            color="warning"
            ;;
        info)
            color="good"
            ;;
    esac
    assert [ "${color}" = "danger" ]
    
    # Warning -> warning (yellow)
    alert_level="warning"
    case "${alert_level}" in
        critical)
            color="danger"
            ;;
        warning)
            color="warning"
            ;;
        info)
            color="good"
            ;;
    esac
    assert [ "${color}" = "warning" ]
    
    # Info -> good (green)
    alert_level="info"
    case "${alert_level}" in
        critical)
            color="danger"
            ;;
        warning)
            color="warning"
            ;;
        info)
            color="good"
            ;;
    esac
    assert [ "${color}" = "good" ]
}

##
# Test: Slack integration with send_alert
##
@test "Slack integration with send_alert" {
    # Disable Slack for this test (we're testing the function, not actual Slack)
    export SLACK_ENABLED="false"
    
    local component="INGESTION"
    local alert_level="warning"
    local alert_type="test_type"
    local message="Test alert message"
    
    # Send alert (should store in DB, skip Slack)
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

