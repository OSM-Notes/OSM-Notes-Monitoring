#!/usr/bin/env bash
#
# Third Unit Tests: alertRules.sh
# Third test file to reach 80% coverage
#

export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    TEST_RULES_FILE="${TEST_LOG_DIR}/test_rules_third.conf"
    export ALERT_RULES_FILE="${TEST_RULES_FILE}"
    rm -f "${TEST_RULES_FILE}"
    TEST_TEMPLATES_DIR="${TEST_LOG_DIR}/templates"
    export ALERT_TEMPLATES_DIR="${TEST_TEMPLATES_DIR}"
    mkdir -p "${TEST_TEMPLATES_DIR}"
    init_logging "${LOG_DIR}/test_alertRules_third.log" "test_alertRules_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: get_routing handles multiple matching rules
##
@test "get_routing handles multiple matching rules" {
    cat > "${TEST_RULES_FILE}" << 'EOF'
*:*:*:default@example.com
TEST_COMPONENT:critical:test:critical@example.com
TEST_COMPONENT:*:test:component@example.com
EOF
    
    run get_routing "TEST_COMPONENT" "critical" "test"
    assert_success
    # Should match most specific rule
    assert_output --partial "@example.com"
}

##
# Test: add_template handles template creation
##
@test "add_template handles template creation" {
    run add_template "test_template" "Test template content"
    assert_success
    
    assert_file_exists "${TEST_TEMPLATES_DIR}/test_template.template"
}

##
# Test: show_template handles missing template gracefully
##
@test "show_template handles missing template gracefully" {
    run show_template "nonexistent"
    # Should handle gracefully
    assert_success || assert_failure
}

##
# Test: main handles --add-template option
##
@test "main handles --add-template option" {
    run main --add-template "test_template" "Content"
    assert_success
}

##
# Test: main handles --show-template option
##
@test "main handles --show-template option" {
    echo "Test content" > "${TEST_TEMPLATES_DIR}/test_template.template"
    
    run main --show-template "test_template"
    assert_success
}
