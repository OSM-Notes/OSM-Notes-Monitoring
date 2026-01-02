#!/usr/bin/env bats
#
# Third Unit Tests: updateDashboard.sh
# Third test file to reach 80% coverage
#

export TEST_COMPONENT="DASHBOARD"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_DIR}/test_updateDashboard_third.log" "test_updateDashboard_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: update_dashboard handles partial update
##
@test "update_dashboard handles partial update" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ UPDATE.*dashboards ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run update_dashboard "test_dashboard" "title" "New Title"
    assert_success
}

##
# Test: update_dashboard handles full dashboard update
##
@test "update_dashboard handles full dashboard update" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ UPDATE.*dashboards ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    local dashboard_json='{"title":"Test","panels":[]}'
    run update_dashboard "test_dashboard" "" "${dashboard_json}"
    assert_success
}

##
# Test: main handles --field option
##
@test "main handles --field option" {
    # Mock update_dashboard
    # shellcheck disable=SC2317
    function update_dashboard() {
        return 0
    }
    export -f update_dashboard
    
    run main --dashboard "test_dashboard" --field "title" --value "New Title"
    assert_success
}
