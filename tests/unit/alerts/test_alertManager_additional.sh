#!/usr/bin/env bash
#
# Additional Unit Tests: Alert Manager
# Additional tests for alert manager to increase coverage
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

# Set TEST_MODE and LOG_DIR before loading anything
export TEST_MODE=true
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
mkdir -p "${TEST_LOG_DIR}"
TEST_LOG_DIR="$(cd "${BATS_TEST_DIRNAME}/../../tmp/logs" && pwd)"
export TEST_LOG_DIR
export LOG_DIR="${TEST_LOG_DIR}"
export LOG_FILE="${LOG_DIR}/test_alertManager_additional.log"
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../../.."

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
source "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertManager.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    init_logging "${LOG_FILE}" "test_alertManager_additional"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: list_alerts handles empty result
##
@test "list_alerts handles empty result gracefully" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run list_alerts
    assert_success
}

##
# Test: show_alert handles missing alert ID
##
@test "show_alert handles missing alert ID" {
    run show_alert ""
    assert_failure
}

##
# Test: acknowledge_alert handles invalid alert ID
##
@test "acknowledge_alert handles invalid alert ID" {
    # Mock psql to return no rows
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ UPDATE.*alerts ]]; then
            echo "0"  # No rows updated
            return 0
        fi
        return 1
    }
    export -f psql
    
    run acknowledge_alert "99999" "test_user"
    assert_failure
}

##
# Test: resolve_alert handles invalid alert ID
##
@test "resolve_alert handles invalid alert ID" {
    # Mock psql to return no rows
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ UPDATE.*alerts ]]; then
            echo "0"  # No rows updated
            return 0
        fi
        return 1
    }
    export -f psql
    
    run resolve_alert "99999" "test_user"
    assert_failure
}

##
# Test: aggregate_alerts handles empty result
##
@test "aggregate_alerts handles empty result" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run aggregate_alerts
    assert_success
}

##
# Test: show_history handles limit parameter
##
@test "show_history uses limit parameter" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ LIMIT.*10 ]]; then
            echo "1|critical|test|2025-12-28"
            return 0
        fi
        return 1
    }
    export -f psql
    
    run show_history "10"
    assert_success
}

##
# Test: show_stats handles database error
##
@test "show_stats handles database error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run show_stats
    assert_failure
}

##
# Test: cleanup_alerts handles zero days
##
@test "cleanup_alerts handles zero days" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ DELETE.*alerts ]]; then
            echo "0"  # No rows deleted
            return 0
        fi
        return 1
    }
    export -f psql
    
    run cleanup_alerts "0"
    assert_success
}

##
# Test: main handles --list option
##
@test "main handles --list option" {
    # Mock list_alerts
    # shellcheck disable=SC2317
    function list_alerts() {
        return 0
    }
    export -f list_alerts
    
    run main --list
    assert_success
}

##
# Test: main handles --show option
##
@test "main handles --show option" {
    # Mock show_alert
    # shellcheck disable=SC2317
    function show_alert() {
        return 0
    }
    export -f show_alert
    
    run main --show "1"
    assert_success
}

##
# Test: main handles --ack option
##
@test "main handles --ack option" {
    # Mock acknowledge_alert
    # shellcheck disable=SC2317
    function acknowledge_alert() {
        return 0
    }
    export -f acknowledge_alert
    
    run main --ack "1" "test_user"
    assert_success
}

##
# Test: main handles --resolve option
##
@test "main handles --resolve option" {
    # Mock resolve_alert
    # shellcheck disable=SC2317
    function resolve_alert() {
        return 0
    }
    export -f resolve_alert
    
    run main --resolve "1" "test_user"
    assert_success
}

##
# Test: main handles --aggregate option
##
@test "main handles --aggregate option" {
    # Mock aggregate_alerts
    # shellcheck disable=SC2317
    function aggregate_alerts() {
        return 0
    }
    export -f aggregate_alerts
    
    run main --aggregate
    assert_success
}

##
# Test: main handles --history option
##
@test "main handles --history option" {
    # Mock show_history
    # shellcheck disable=SC2317
    function show_history() {
        return 0
    }
    export -f show_history
    
    run main --history "10"
    assert_success
}

##
# Test: main handles --stats option
##
@test "main handles --stats option" {
    # Mock show_stats
    # shellcheck disable=SC2317
    function show_stats() {
        return 0
    }
    export -f show_stats
    
    run main --stats
    assert_success
}

##
# Test: main handles --cleanup option
##
@test "main handles --cleanup option" {
    # Mock cleanup_alerts
    # shellcheck disable=SC2317
    function cleanup_alerts() {
        return 0
    }
    export -f cleanup_alerts
    
    run main --cleanup "30"
    assert_success
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
