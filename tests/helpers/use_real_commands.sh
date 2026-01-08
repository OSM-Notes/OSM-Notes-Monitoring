#!/usr/bin/env bash
#
# Helper functions to use real commands instead of mocks when safe
# This improves code coverage by executing real code paths
#
# Usage:
#   source tests/helpers/use_real_commands.sh
#   setup_real_git_if_available
#
# Version: 1.0.0
# Date: 2026-01-08
#

##
# Setup git to use real git if available, otherwise mock
# This should be called in test setup() functions
##
setup_real_git_if_available() {
    if command -v git >/dev/null 2>&1; then
        # Use real git - no need to mock
        # Git is safe to use in tests as we control the test directories
        return 0
    else
        # Mock git if not available
        # shellcheck disable=SC2317
        git() {
            echo "mocked git"
            return 0
        }
        export -f git
        return 1
    fi
}

##
# Setup psql to use real database if available, otherwise mock
# This should be called in test setup() functions
##
setup_real_psql_if_available() {
    # Check if database connection is available
    if command -v psql >/dev/null 2>&1; then
        # Try to connect to test database
        # shellcheck disable=SC2119
        if check_database_connection 2>/dev/null; then
            # Real database available - use real psql
            export USE_REAL_DB=true
            return 0
        fi
    fi
    
    # Mock psql if database not available
    # shellcheck disable=SC2317
    psql() {
        echo "mocked"
        return 0
    }
    export -f psql
    export USE_REAL_DB=false
    return 1
}

##
# Check if database connection is available
# This function should be available from test_helper.bash
# shellcheck disable=SC2120
##
check_database_connection() {
    # This function should be defined in test_helper.bash
    # If not, we'll define a simple version here
    # Arguments may be passed if function is overridden elsewhere
    if type check_database_connection >/dev/null 2>&1; then
        command check_database_connection "$@"
    else
        # Simple check: try to connect to default test database
        local dbname="${TEST_DB_NAME:-osm_notes_monitoring_test}"
        local dbhost="${DBHOST:-localhost}"
        local dbport="${DBPORT:-5432}"
        local dbuser="${DBUSER:-${USER:-postgres}}"
        
        if timeout 2 psql -h "${dbhost}" -p "${dbport}" -U "${dbuser}" -d "${dbname}" -c "SELECT 1" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
}

# Export functions so they can be used in tests
export -f setup_real_git_if_available
export -f setup_real_psql_if_available
