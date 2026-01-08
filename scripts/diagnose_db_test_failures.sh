#!/usr/bin/env bash
#
# Diagnose Database Test Failures
# Identifies which integration tests fail due to database connection issues
# and determines if it's a configuration problem or database unavailability
#
# Version: 1.0.0
# Date: 2026-01-07
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Output file
readonly OUTPUT_FILE="${PROJECT_ROOT}/coverage/db_test_diagnosis.txt"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check database availability with different configurations
##
check_db_availability() {
    local dbhost="${1}"
    local dbport="${2}"
    local dbuser="${3}"
    local dbname="${4}"
    local dbpassword="${5:-}"
    
    # Try connection with timeout
    local psql_cmd
    if [[ -n "${dbpassword}" ]]; then
        psql_cmd="PGPASSWORD=\"${dbpassword}\" psql"
    else
        psql_cmd="psql"
    fi
    
    # Use timeout to avoid hanging
    if timeout 2 bash -c "eval ${psql_cmd} -h \"${dbhost}\" -p \"${dbport}\" -U \"${dbuser}\" -d \"${dbname}\" -c 'SELECT 1' > /dev/null 2>&1"; then
        return 0
    else
        return 1
    fi
}

##
# Extract database configuration from test file
##
extract_db_config() {
    local test_file="${1}"
    
    local dbhost="localhost"
    local dbport="5432"
    local dbuser="postgres"
    local dbname="osm_notes_monitoring_test"  # Default, will be overridden if found in file
    local dbpassword="${PGPASSWORD:-}"
    
    # Extract DBHOST
    if grep -q "export DBHOST=" "${test_file}" 2>/dev/null; then
        dbhost=$(grep "export DBHOST=" "${test_file}" | head -n 1 | sed -E "s/.*DBHOST=\"?([^\"]+)\"?.*/\1/" | sed -E "s/.*DBHOST=\$\{([^}]+)\}.*/\1/")
        # Handle variable substitution
        if [[ "${dbhost}" =~ ^\$\{.*\}$ ]]; then
            dbhost=$(eval echo "${dbhost}")
        fi
    fi
    
    # Extract DBPORT
    if grep -q "export DBPORT=" "${test_file}" 2>/dev/null; then
        dbport=$(grep "export DBPORT=" "${test_file}" | head -n 1 | sed -E "s/.*DBPORT=\"?([^\"]+)\"?.*/\1/" | sed -E "s/.*DBPORT=\$\{([^}]+)\}.*/\1/")
        # Handle variable substitution
        if [[ "${dbport}" =~ ^\$\{.*\}$ ]]; then
            dbport=$(eval echo "${dbport}")
        fi
    fi
    
    # Extract DBUSER
    if grep -q "export DBUSER=" "${test_file}" 2>/dev/null; then
        dbuser=$(grep "export DBUSER=" "${test_file}" | head -n 1 | sed -E "s/.*DBUSER=\"?([^\"]+)\"?.*/\1/" | sed -E "s/.*DBUSER=\$\{([^}]+)\}.*/\1/")
        # Handle variable substitution
        if [[ "${dbuser}" =~ ^\$\{.*\}$ ]]; then
            dbuser=$(eval echo "${dbuser}")
        fi
    fi
    
    # Extract DBNAME/TEST_DB_NAME
    if grep -q "export DBNAME=" "${test_file}" 2>/dev/null; then
        dbname=$(grep "export DBNAME=" "${test_file}" | head -n 1 | sed -E "s/.*DBNAME=\"?([^\"]+)\"?.*/\1/" | sed -E "s/.*DBNAME=\$\{([^}]+)\}.*/\1/")
        # Handle variable substitution
        if [[ "${dbname}" =~ ^\$\{.*\}$ ]]; then
            dbname=$(eval echo "${dbname}")
        fi
    elif grep -q "export TEST_DB_NAME=" "${test_file}" 2>/dev/null; then
        dbname=$(grep "export TEST_DB_NAME=" "${test_file}" | head -n 1 | sed -E "s/.*TEST_DB_NAME=\"?([^\"]+)\"?.*/\1/" | sed -E "s/.*TEST_DB_NAME=\$\{([^}]+)\}.*/\1/")
        # Handle variable substitution
        if [[ "${dbname}" =~ ^\$\{.*\}$ ]]; then
            dbname=$(eval echo "${dbname}")
        fi
    fi
    
    echo "${dbhost}|${dbport}|${dbuser}|${dbname}|${dbpassword}"
}

##
# Run a test and capture database-related failures
##
run_test_with_db_check() {
    local test_file="${1}"
    local test_name
    test_name=$(basename "${test_file}")
    
    print_message "${BLUE}" "Testing: ${test_name}"
    
    # Extract DB config from test file
    local db_config
    db_config=$(extract_db_config "${test_file}")
    local IFS='|'
    read -r dbhost dbport dbuser dbname dbpassword <<< "${db_config}"
    
    # Check if test uses database
    if ! grep -q "skip_if_database_not_available\|check_database_connection\|psql" "${test_file}" 2>/dev/null; then
        echo "  Status: No database usage detected"
        return 0
    fi
    
    # Check database availability
    print_message "${YELLOW}" "  Checking DB: ${dbuser}@${dbhost}:${dbport}/${dbname}"
    
    if check_db_availability "${dbhost}" "${dbport}" "${dbuser}" "${dbname}" "${dbpassword}"; then
        print_message "${GREEN}" "  ✓ Database is available"
        
        # Try running the test with timeout
        local test_output
        test_output=$(timeout 30 bats "${test_file}" 2>&1 || true)
        
        # Check for database-related errors
        if echo "${test_output}" | grep -qi "database not available\|connection refused\|authentication failed\|password\|timeout\|connection.*failed"; then
            print_message "${RED}" "  ✗ Test failed with DB error (but DB is available - config issue?)"
            echo "    Config: ${dbuser}@${dbhost}:${dbport}/${dbname}"
            echo "    Error: $(echo "${test_output}" | grep -i "database\|connection\|password\|timeout" | head -n 3)"
            return 1
        elif echo "${test_output}" | grep -qi "skip.*database"; then
            print_message "${YELLOW}" "  ⚠ Test skipped (database check)"
            return 0
        else
            print_message "${GREEN}" "  ✓ Test passed or skipped normally"
            return 0
        fi
    else
        print_message "${RED}" "  ✗ Database is NOT available"
        echo "    Config: ${dbuser}@${dbhost}:${dbport}/${dbname}"
        
        # Check if it's a configuration issue
        local config_issue=false
        
        # Check if using wrong host/port
        if [[ "${dbhost}" != "localhost" ]] && [[ "${dbhost}" != "127.0.0.1" ]]; then
            if check_db_availability "localhost" "${dbport}" "${dbuser}" "${dbname}" "${dbpassword}"; then
                print_message "${YELLOW}" "    ⚠ DB available at localhost but test uses ${dbhost} (config issue)"
                config_issue=true
            fi
        fi
        
        # Check if using wrong port
        if [[ "${dbport}" != "5432" ]]; then
            if check_db_availability "${dbhost}" "5432" "${dbuser}" "${dbname}" "${dbpassword}"; then
                print_message "${YELLOW}" "    ⚠ DB available on port 5432 but test uses ${dbport} (config issue)"
                config_issue=true
            fi
        fi
        
        # Check if using wrong user
        if [[ "${dbuser}" != "${USER:-postgres}" ]] && [[ "${dbuser}" != "postgres" ]]; then
            if check_db_availability "${dbhost}" "${dbport}" "${USER:-postgres}" "${dbname}" "${dbpassword}"; then
                print_message "${YELLOW}" "    ⚠ DB available with user ${USER:-postgres} but test uses ${dbuser} (config issue)"
                config_issue=true
            fi
        fi
        
        # Check if database doesn't exist
        if check_db_availability "${dbhost}" "${dbport}" "${dbuser}" "postgres" "${dbpassword}"; then
            print_message "${YELLOW}" "    ⚠ Server is available but database '${dbname}' may not exist (config issue)"
            config_issue=true
        fi
        
        if [[ "${config_issue}" == "true" ]]; then
            return 2  # Configuration issue
        else
            return 1  # Database unavailable
        fi
    fi
}

##
# Main function
##
main() {
    print_message "${GREEN}" "Database Test Failure Diagnosis"
    echo ""
    
    mkdir -p "${PROJECT_ROOT}/coverage"
    
    # Find all integration test files
    local test_files=()
    while IFS= read -r -d '' test_file; do
        test_files+=("${test_file}")
    done < <(find "${PROJECT_ROOT}/tests/integration" -name "*.sh" -type f -print0 2>/dev/null | sort -z)
    
    print_message "${BLUE}" "Found ${#test_files[@]} integration test files"
    echo ""
    
    # Check PostgreSQL client availability
    if ! command -v psql > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: psql not found. Cannot check database availability."
        exit 1
    fi
    
    # Check default database availability
    print_message "${BLUE}" "Checking default database configuration..."
    local default_available=false
    if check_db_availability "localhost" "5432" "${USER:-postgres}" "${TEST_DB_NAME:-osm_notes_monitoring_test}" "${PGPASSWORD:-}"; then
        print_message "${GREEN}" "✓ Default database is available"
        default_available=true
    elif check_db_availability "localhost" "5432" "postgres" "${TEST_DB_NAME:-osm_notes_monitoring_test}" "${PGPASSWORD:-}"; then
        print_message "${GREEN}" "✓ Default database is available (with postgres user)"
        default_available=true
    else
        print_message "${YELLOW}" "⚠ Default database is NOT available"
    fi
    echo ""
    
    # Analyze each test
    local db_unavailable_count=0
    local config_issue_count=0
    local passed_count=0
    local no_db_count=0
    
    {
        echo "Database Test Failure Diagnosis Report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
        echo ""
        echo "Default Database Status: ${default_available}"
        echo ""
        echo "Test Analysis:"
        echo "--------------------------------------------------------------------------------"
        printf "%-50s %-15s %-30s\n" "Test File" "Status" "Issue"
        echo "--------------------------------------------------------------------------------"
    } > "${OUTPUT_FILE}"
    
    for test_file in "${test_files[@]}"; do
        local test_name
        test_name=$(basename "${test_file}")
        local result
        run_test_with_db_check "${test_file}" || result=$?
        
        case "${result:-0}" in
            0)
                passed_count=$((passed_count + 1))
                printf "%-50s %-15s %-30s\n" "${test_name}" "OK" "" >> "${OUTPUT_FILE}"
                ;;
            1)
                db_unavailable_count=$((db_unavailable_count + 1))
                printf "%-50s %-15s %-30s\n" "${test_name}" "DB UNAVAILABLE" "Database not accessible" >> "${OUTPUT_FILE}"
                ;;
            2)
                config_issue_count=$((config_issue_count + 1))
                printf "%-50s %-15s %-30s\n" "${test_name}" "CONFIG ISSUE" "Wrong host/port/user/db" >> "${OUTPUT_FILE}"
                ;;
            *)
                no_db_count=$((no_db_count + 1))
                printf "%-50s %-15s %-30s\n" "${test_name}" "NO DB USAGE" "" >> "${OUTPUT_FILE}"
                ;;
        esac
        echo ""
    done
    
    # Summary
    {
        echo ""
        echo "--------------------------------------------------------------------------------"
        echo "Summary:"
        echo "  Total tests: ${#test_files[@]}"
        echo "  Passed/OK: ${passed_count}"
        echo "  Database unavailable: ${db_unavailable_count}"
        echo "  Configuration issues: ${config_issue_count}"
        echo "  No database usage: ${no_db_count}"
        echo ""
        echo "Recommendations:"
        if [[ ${config_issue_count} -gt 0 ]]; then
            echo "  - Fix configuration issues in ${config_issue_count} test(s)"
            echo "  - Review DBHOST, DBPORT, DBUSER, DBNAME settings"
        fi
        if [[ ${db_unavailable_count} -gt 0 ]]; then
            echo "  - Ensure database is running and accessible"
            echo "  - Create test database: ${TEST_DB_NAME:-osm_notes_monitoring_test}"
            echo "  - Check PostgreSQL service status"
        fi
    } >> "${OUTPUT_FILE}"
    
    print_message "${GREEN}" "✓ Diagnosis complete!"
    print_message "${BLUE}" "Report saved to: ${OUTPUT_FILE}"
    echo ""
    
    # Show summary
    tail -20 "${OUTPUT_FILE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
