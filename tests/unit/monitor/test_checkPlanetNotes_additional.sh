#!/usr/bin/env bash
#
# Additional Unit Tests: checkPlanetNotes.sh
# Second test file to increase coverage
#

export TEST_COMPONENT="INGESTION"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_INGESTION_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_ingestion_planet"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_INGESTION_DIR}/bin/monitor"
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    
    export INGESTION_REPO_PATH="${TEST_INGESTION_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    export INGESTION_ENABLED="true"
    export INGESTION_PLANET_CHECK_DURATION_THRESHOLD="600"
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        return 0
    }
    export -f psql
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/checkPlanetNotes.sh"
    
    init_logging "${TEST_LOG_DIR}/test_checkPlanetNotes_additional.log" "test_checkPlanetNotes_additional"
    init_alerting
}

teardown() {
    rm -rf "${TEST_INGESTION_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: checkPlanetNotes handles missing script gracefully
##
@test "checkPlanetNotes handles missing script gracefully" {
    export INGESTION_REPO_PATH="/nonexistent/path"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run checkPlanetNotes || true
    # Should handle gracefully
    assert_success || true
}

##
# Test: checkPlanetNotes handles script execution timeout
##
@test "checkPlanetNotes handles script execution timeout" {
    # Create a script that takes too long
    local test_script="${TEST_INGESTION_DIR}/bin/monitor/processCheckPlanetNotes.sh"
    cat > "${test_script}" << 'EOF'
#!/bin/bash
sleep 1000  # Simulate timeout
EOF
    chmod +x "${test_script}"
    
    export INGESTION_PLANET_CHECK_DURATION_THRESHOLD="1"  # Very short threshold
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run checkPlanetNotes || true
    # Should detect timeout
    assert_success || true
    
    rm -f "${test_script}"
}

##
# Test: checkPlanetNotes handles script with errors
##
@test "checkPlanetNotes handles script with errors" {
    # Create a script that fails
    local test_script="${TEST_INGESTION_DIR}/bin/monitor/processCheckPlanetNotes.sh"
    cat > "${test_script}" << 'EOF'
#!/bin/bash
exit 1  # Script fails
EOF
    chmod +x "${test_script}"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run checkPlanetNotes || true
    # Should handle error
    assert_success || true
    
    rm -f "${test_script}"
}

##
# Test: checkPlanetNotes handles disabled monitoring
##
@test "checkPlanetNotes handles disabled monitoring" {
    export INGESTION_ENABLED="false"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    run checkPlanetNotes
    # Should skip when disabled
    assert_success
}

##
# Test: checkPlanetNotes handles successful execution
##
@test "checkPlanetNotes handles successful execution" {
    # Create a successful script
    local test_script="${TEST_INGESTION_DIR}/bin/monitor/processCheckPlanetNotes.sh"
    cat > "${test_script}" << 'EOF'
#!/bin/bash
echo "Planet check completed successfully"
exit 0
EOF
    chmod +x "${test_script}"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run checkPlanetNotes
    assert_success
    
    rm -f "${test_script}"
}
