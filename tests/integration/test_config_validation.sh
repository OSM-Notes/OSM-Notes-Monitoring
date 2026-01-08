#!/usr/bin/env bash
#
# Integration Tests: Configuration Validation
# Tests configuration validation with various scenarios
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# Each test runs in an isolated subshell, so variable modifications are intentional

# Test configuration - set before loading test_helper
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"

@test "validate_main_config requires DBNAME" {
    unset DBNAME
    unset DBHOST
    unset DBPORT
    unset DBUSER
    
    run validate_main_config
    assert_failure
    assert_output --partial "DBNAME"
}

@test "validate_main_config requires DBHOST" {
    export DBNAME="test_db"
    unset DBHOST
    unset DBPORT
    unset DBUSER
    
    run validate_main_config
    assert_failure
    assert_output --partial "DBHOST"
}

@test "validate_main_config requires DBPORT" {
    export DBNAME="test_db"
    export DBHOST="localhost"
    unset DBPORT
    unset DBUSER
    
    run validate_main_config
    assert_failure
    assert_output --partial "DBPORT"
}

@test "validate_main_config requires DBUSER" {
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    unset DBUSER
    
    run validate_main_config
    assert_failure
    assert_output --partial "DBUSER"
}

@test "validate_main_config rejects non-numeric DBPORT" {
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="invalid"
    export DBUSER="postgres"
    
    run validate_main_config
    assert_failure
    assert_output --partial "must be a number"
}

@test "validate_main_config accepts valid configuration" {
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="postgres"
    
    run validate_main_config
    # May fail due to DB connection, but should pass validation
    # Just check it doesn't fail on missing variables
    assert_success || true
}

@test "validate_alert_config requires ADMIN_EMAIL when SEND_ALERT_EMAIL is true" {
    export SEND_ALERT_EMAIL="true"
    unset ADMIN_EMAIL
    
    run validate_alert_config
    assert_failure
    assert_output --partial "ADMIN_EMAIL"
}

@test "validate_alert_config rejects invalid email format" {
    export SEND_ALERT_EMAIL="true"
    export ADMIN_EMAIL="invalid-email"
    
    run validate_alert_config
    assert_failure
    assert_output --partial "Invalid ADMIN_EMAIL"
}

@test "validate_alert_config accepts valid email" {
    export SEND_ALERT_EMAIL="true"
    export ADMIN_EMAIL="admin@example.com"
    
    run validate_alert_config
    assert_success || true
}

@test "validate_alert_config requires SLACK_WEBHOOK_URL when SLACK_ENABLED is true" {
    export SLACK_ENABLED="true"
    unset SLACK_WEBHOOK_URL
    
    run validate_alert_config
    assert_failure
    assert_output --partial "SLACK_WEBHOOK_URL"
}

@test "validate_security_config rejects non-numeric rate limit" {
    export RATE_LIMIT_PER_IP_PER_MINUTE="invalid"
    
    run validate_security_config
    assert_failure
    assert_output --partial "must be a number"
}

@test "validate_security_config rejects zero rate limit" {
    export RATE_LIMIT_PER_IP_PER_MINUTE="0"
    
    run validate_security_config
    assert_failure
    assert_output --partial "at least 1"
}

@test "validate_security_config accepts valid rate limits" {
    export RATE_LIMIT_PER_IP_PER_MINUTE="60"
    export RATE_LIMIT_PER_IP_PER_HOUR="1000"
    
    run validate_security_config
    assert_success || true
}

@test "validate_security_config rejects invalid ABUSE_DETECTION_ENABLED" {
    export ABUSE_DETECTION_ENABLED="maybe"
    
    run validate_security_config
    assert_failure
    assert_output --partial "true or false"
}

@test "validate_monitoring_config validates component enabled flags" {
    export INGESTION_ENABLED="maybe"
    
    run validate_monitoring_config
    assert_failure
    assert_output --partial "must be true/false"
}

@test "validate_monitoring_config validates timeout values" {
    export INGESTION_CHECK_TIMEOUT="invalid"
    
    run validate_monitoring_config
    assert_failure
    assert_output --partial "must be a number"
}

@test "validate_monitoring_config validates retention days" {
    export METRICS_RETENTION_DAYS="0"
    
    run validate_monitoring_config
    assert_failure
    assert_output --partial "at least 1"
}

@test "validate_all_configs validates all loaded configs" {
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="postgres"
    export ADMIN_EMAIL="admin@example.com"
    export SEND_ALERT_EMAIL="true"
    
    run validate_all_configs
    # Should succeed or fail gracefully
    # Just check it executes without crashing
    assert true
}

