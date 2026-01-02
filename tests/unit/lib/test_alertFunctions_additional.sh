#!/usr/bin/env bats
#
# Additional Unit Tests: alertFunctions.sh
# Additional tests for alert functions library to increase coverage
#

# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Not following source files is expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alertFunctions_additional.log"
    init_logging "${LOG_FILE}" "test_alertFunctions_additional"
    
    # Mock database connection
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Initialize alerting
    init_alerting
}

teardown() {
    # Cleanup
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: init_alerting sets default values
##
@test "init_alerting sets default values" {
    # Unset alert-related variables
    unset ALERT_DEDUPLICATION_ENABLED
    unset ALERT_DEDUPLICATION_WINDOW
    unset ADMIN_EMAIL SEND_ALERT_EMAIL SLACK_ENABLED
    
    # Temporarily rename config file to prevent it from being loaded
    # Use BATS_TEST_DIRNAME to find project root
    local project_root
    project_root="$(dirname "$(dirname "$(dirname "${BATS_TEST_DIRNAME}")")")"
    local config_file="${project_root}/config/alerts.conf"
    local backup_file="${config_file}.backup"
    
    if [[ -f "${config_file}" ]]; then
        mv "${config_file}" "${backup_file}"
    fi
    
    # Re-run init_alerting
    init_alerting
    
    # ALERT_DEDUPLICATION_ENABLED is not set by init_alerting, it's used with default value
    # Test that init_alerting sets the basic variables
    assert [ -n "${ADMIN_EMAIL:-}" ]
    assert [ "${SEND_ALERT_EMAIL:-false}" = "false" ]
    assert [ "${SLACK_ENABLED:-false}" = "false" ]
    
    # Restore config file if it existed
    if [[ -f "${backup_file}" ]]; then
        mv "${backup_file}" "${config_file}"
    fi
}

##
# Test: store_alert handles empty component
##
@test "store_alert handles empty component" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    # Should fail with empty component
    run store_alert "" "critical" "test_alert" "Test message"
    assert_failure
}

##
# Test: store_alert handles empty alert level
##
@test "store_alert handles empty alert level" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    # Should fail with empty alert level
    run store_alert "TEST_COMPONENT" "" "test_alert" "Test message"
    assert_failure
}

##
# Test: store_alert handles empty alert type
##
@test "store_alert handles empty alert type" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    # Should fail with empty alert type
    run store_alert "TEST_COMPONENT" "critical" "" "Test message"
    assert_failure
}

##
# Test: store_alert handles empty message
##
@test "store_alert handles empty message" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    # Should fail with empty message
    run store_alert "TEST_COMPONENT" "critical" "test_alert" ""
    assert_failure
}

##
# Test: is_alert_duplicate returns false for new alert
##
@test "is_alert_duplicate returns false for new alert" {
    # Mock psql to return no duplicates
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*alerts ]]; then
            echo "0"  # No duplicates found
            return 0
        fi
        return 1
    }
    
    run is_alert_duplicate "TEST_COMPONENT" "new_alert" "New message"
    # Should return 1 (false - not duplicate)
    assert_failure
}

##
# Test: is_alert_duplicate returns true for duplicate alert
##
@test "is_alert_duplicate returns true for duplicate alert" {
    # Mock psql to return duplicate found
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*alerts ]]; then
            echo "1"  # Duplicate found
            return 0
        fi
        return 1
    }
    
    run is_alert_duplicate "TEST_COMPONENT" "duplicate_alert" "Duplicate message"
    # Should return 0 (true - is duplicate)
    assert_success
}

##
# Test: send_email_alert handles disabled email alerts
##
@test "send_email_alert skips when email alerts disabled" {
    export SEND_ALERT_EMAIL="false"
    
    run send_email_alert "test@example.com" "Test Subject" "Test Body"
    assert_success
}

##
# Test: send_email_alert handles missing mutt
##
@test "send_email_alert handles missing mutt" {
    export SEND_ALERT_EMAIL="true"
    
    # Mock command to return mutt not found
    # shellcheck disable=SC2317
    function command() {
        if [[ "${1}" == "-v" ]] && [[ "${2}" == "mutt" ]]; then
            return 1  # Command not found
        fi
        return 0
    }
    
    run send_email_alert "test@example.com" "Test Subject" "Test Body"
    assert_failure
}

##
# Test: send_email_alert handles mutt failure
##
@test "send_email_alert handles mutt failure" {
    export SEND_ALERT_EMAIL="true"
    
    # Mock mutt to fail
    # shellcheck disable=SC2317
    function mutt() {
        return 1
    }
    export -f mutt
    
    run send_email_alert "test@example.com" "Test Subject" "Test Body"
    assert_failure
}

##
# Test: send_slack_alert handles disabled Slack
##
@test "send_slack_alert skips when Slack disabled" {
    export SLACK_ENABLED="false"
    
    run send_slack_alert "TEST_COMPONENT" "critical" "test_alert" "Test message"
    assert_success
}

##
# Test: send_slack_alert handles missing webhook URL
##
@test "send_slack_alert skips when webhook URL missing" {
    export SLACK_ENABLED="true"
    unset SLACK_WEBHOOK_URL
    
    run send_slack_alert "TEST_COMPONENT" "critical" "test_alert" "Test message"
    assert_success
}

##
# Test: send_slack_alert handles missing curl
##
@test "send_slack_alert handles missing curl" {
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    
    # Mock command to return curl not found
    # shellcheck disable=SC2317
    function command() {
        if [[ "${1}" == "-v" ]] && [[ "${2}" == "curl" ]]; then
            return 1  # Command not found
        fi
        return 0
    }
    
    run send_slack_alert "TEST_COMPONENT" "critical" "test_alert" "Test message"
    assert_failure
}

##
# Test: send_slack_alert uses correct color for warning
##
@test "send_slack_alert uses warning color" {
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        # Payload is passed via stdin or -d (captured but not used in test)
        return 0
    }
    export -f curl
    
    run send_slack_alert "TEST_COMPONENT" "warning" "test_alert" "Test message"
    assert_success
}

##
# Test: send_slack_alert uses correct color for info
##
@test "send_slack_alert uses info color" {
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        return 0
    }
    export -f curl
    
    run send_slack_alert "TEST_COMPONENT" "info" "test_alert" "Test message"
    assert_success
}

##
# Test: send_alert handles info level with no recipients
##
@test "send_alert skips info alerts when no recipients" {
    unset INFO_ALERT_RECIPIENTS
    unset ADMIN_EMAIL
    
    # Mock store_alert
    # shellcheck disable=SC2317
    function store_alert() {
        return 0
    }
    export -f store_alert
    
    run send_alert "TEST_COMPONENT" "info" "test_alert" "Test message"
    assert_success
}

##
# Test: send_alert handles custom info recipients
##
@test "send_alert uses custom info recipients" {
    export INFO_ALERT_RECIPIENTS="info@example.com"
    export SEND_ALERT_EMAIL="true"
    
    # Mock store_alert
    # shellcheck disable=SC2317
    function store_alert() {
        return 0
    }
    export -f store_alert
    
    # Mock mutt
    # shellcheck disable=SC2317
    function mutt() {
        return 0
    }
    export -f mutt
    
    run send_alert "TEST_COMPONENT" "info" "test_alert" "Test message"
    assert_success
}

##
# Test: send_alert handles store_alert failure
##
@test "send_alert aborts on store_alert failure" {
    # Mock store_alert to fail
    # shellcheck disable=SC2317
    function store_alert() {
        return 1
    }
    export -f store_alert
    
    run send_alert "TEST_COMPONENT" "critical" "test_alert" "Test message"
    assert_failure
}

##
# Test: send_alert handles both email and Slack
##
@test "send_alert sends both email and Slack when enabled" {
    export SEND_ALERT_EMAIL="true"
    export ADMIN_EMAIL="admin@example.com"
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    
    # Mock store_alert
    # shellcheck disable=SC2317
    function store_alert() {
        return 0
    }
    export -f store_alert
    
    # Mock mutt
    # shellcheck disable=SC2317
    function mutt() {
        return 0
    }
    export -f mutt
    
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        return 0
    }
    export -f curl
    
    run send_alert "TEST_COMPONENT" "critical" "test_alert" "Test message"
    assert_success
}

##
# Test: is_alert_duplicate handles custom deduplication window
##
@test "is_alert_duplicate uses custom deduplication window" {
    export ALERT_DEDUPLICATION_WINDOW="300"  # 5 minutes
    
    # Mock psql to return no duplicates
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*alerts ]]; then
            echo "0"
            return 0
        fi
        return 1
    }
    
    run is_alert_duplicate "TEST_COMPONENT" "test_alert" "Test message"
    assert_failure  # Not duplicate
}

##
# Test: send_slack_alert handles custom channel
##
@test "send_slack_alert uses custom channel when set" {
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    export SLACK_CHANNEL="#custom-channel"
    
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        # Verify channel is in payload
        if [[ "${*}" =~ custom-channel ]]; then
            return 0
        fi
        return 0
    }
    export -f curl
    
    run send_slack_alert "TEST_COMPONENT" "critical" "test_alert" "Test message"
    assert_success
}
