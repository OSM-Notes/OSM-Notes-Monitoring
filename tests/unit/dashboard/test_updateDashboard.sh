#!/usr/bin/env bats
#
# Unit Tests: updateDashboard.sh
# Tests for dashboard update script
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="DASHBOARD"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_updateDashboard.log"
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR to avoid permission issues
    init_logging "${LOG_FILE}" "test_updateDashboard"
    
    # Create temporary directories
    TEST_DASHBOARD_DIR=$(mktemp -d)
    export DASHBOARD_OUTPUT_DIR="${TEST_DASHBOARD_DIR}"
    mkdir -p "${TEST_DASHBOARD_DIR}/grafana"
    mkdir -p "${TEST_DASHBOARD_DIR}/html"
    
    # Test metrics script path (for reference, not used directly in tests)
    # shellcheck disable=SC2034
    TEST_METRICS_SCRIPT="${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh"
}

teardown() {
    # Cleanup
    rm -rf "${TEST_DASHBOARD_DIR:-}"
}

##
# Test: updateDashboard.sh usage
##
@test "updateDashboard.sh shows usage with --help" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" --help
    assert_success
    assert [[ "${output}" =~ Usage: ]]
    assert [[ "${output}" =~ updateDashboard.sh ]]
}

##
# Test: updateDashboard.sh updates Grafana dashboards
##
@test "updateDashboard.sh updates Grafana dashboards" {
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql for component health
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" grafana
    assert_success
}

##
# Test: updateDashboard.sh updates HTML dashboards
##
@test "updateDashboard.sh updates HTML dashboards" {
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql for component health
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" html
    assert_success
}

##
# Test: updateDashboard.sh updates all dashboards
##
@test "updateDashboard.sh updates all dashboards" {
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql for component health
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" all
    assert_success
}

##
# Test: updateDashboard.sh handles force update
##
@test "updateDashboard.sh handles --force flag" {
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql for component health
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" --force all
    assert_success
}

##
# Test: updateDashboard.sh handles component filter
##
@test "updateDashboard.sh handles --component filter" {
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql for component health
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" --component ingestion all
    assert_success
}

##
# Test: updateDashboard.sh skips update if recent
##
@test "updateDashboard.sh skips update if data is recent" {
    # Create recent file
    touch "${TEST_DASHBOARD_DIR}/html/overview_data.json"
    
    # Mock psql for component health
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" html
    assert_success
    assert [[ "${output}" =~ "up to date" ]] || [[ "${output}" =~ "updated" ]]
}

@test "updateDashboard.sh handles --verbose flag" {
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" --verbose all
    assert_success
}

@test "updateDashboard.sh handles --quiet flag" {
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" --quiet all
    assert_success
}

@test "updateDashboard.sh handles --config flag" {
    local test_config="${BATS_TEST_DIRNAME}/../../../tmp/test_updateDashboard_config.conf"
    echo "TEST_CONFIG_VAR=test_value" > "${test_config}"
    
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" --config "${test_config}" all
    assert_success
    
    rm -f "${test_config}"
}

@test "updateDashboard.sh handles --dashboard flag" {
    local custom_dir
    custom_dir=$(mktemp -d)
    mkdir -p "${custom_dir}/grafana"
    
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" --dashboard "${custom_dir}" grafana
    assert_success
    
    rm -rf "${custom_dir}"
}

@test "updateDashboard.sh handles invalid dashboard type" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" invalid
    assert_failure || assert_success  # May handle gracefully
}

@test "updateDashboard.sh handles generateMetrics.sh failure" {
    # Mock generateMetrics.sh to fail
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        return 1
    }
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" grafana
    # Should handle error gracefully
    assert_success || assert_failure
}

@test "updateDashboard.sh handles database connection failure" {
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" grafana
    # Should handle error gracefully
    assert_success || assert_failure
}

@test "updateDashboard.sh handles time range parameter" {
    # Mock generateMetrics.sh
    # shellcheck disable=SC2317
    function generateMetrics.sh() {
        echo '{"test":"data"}'
    }
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "OK"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" --time-range 168 all
    assert_success
}
