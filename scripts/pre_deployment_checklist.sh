#!/usr/bin/env bash
#
# Pre-Deployment Checklist Script
# Verifies everything is ready for production deployment
#
# Version: 1.0.0
# Date: 2026-01-01
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNINGS=0

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check result
##
check_result() {
    local status="${1}"
    local message="${2}"
    
    case "${status}" in
        PASS)
            print_message "${GREEN}" "  ✓ ${message}"
            ((CHECKS_PASSED++))
            ;;
        FAIL)
            print_message "${RED}" "  ✗ ${message}"
            ((CHECKS_FAILED++))
            ;;
        WARN)
            print_message "${YELLOW}" "  ⚠ ${message}"
            ((CHECKS_WARNINGS++))
            ;;
    esac
}

##
# Check prerequisites
##
check_prerequisites() {
    print_message "${BLUE}" "1. Checking Prerequisites"
    print_message "${BLUE}" "========================="
    
    local missing=()
    local required_commands=("bash" "psql" "curl")
    
    for cmd in "${required_commands[@]}"; do
        if command -v "${cmd}" > /dev/null 2>&1; then
            check_result "PASS" "${cmd} is installed"
        else
            check_result "FAIL" "${cmd} is NOT installed"
            missing+=("${cmd}")
        fi
    done
    
    # Check PostgreSQL version
    if command -v psql > /dev/null 2>&1; then
        local pg_version
        pg_version=$(psql --version | grep -oE '[0-9]+' | head -1)
        if [[ "${pg_version}" -ge 12 ]]; then
            check_result "PASS" "PostgreSQL version ${pg_version} (>= 12)"
        else
            check_result "WARN" "PostgreSQL version ${pg_version} (< 12 recommended)"
        fi
    fi
    
    echo
    return 0
}

##
# Check configuration files
##
check_configuration() {
    print_message "${BLUE}" "2. Checking Configuration Files"
    print_message "${BLUE}" "================================"
    
    local config_files=(
        "etc/properties.sh"
        "config/monitoring.conf"
        "config/alerts.conf"
        "config/security.conf"
    )
    
    for config_file in "${config_files[@]}"; do
        local full_path="${PROJECT_ROOT}/${config_file}"
        
        if [[ -f "${full_path}" ]]; then
            check_result "PASS" "${config_file} exists"
            
            # Check for default values
            if grep -q "example.com\|changeme\|password\|/path/to" "${full_path}" 2>/dev/null; then
                local defaults
                defaults=$(grep -E "example.com|changeme|password|/path/to" "${full_path}" | head -3 | tr '\n' ' ')
                check_result "WARN" "${config_file} contains default values: ${defaults}"
            fi
        else
            check_result "FAIL" "${config_file} is MISSING"
        fi
    done
    
    # Validate configuration
    if [[ -f "${PROJECT_ROOT}/scripts/test_config_validation.sh" ]]; then
        if "${PROJECT_ROOT}/scripts/test_config_validation.sh" > /dev/null 2>&1; then
            check_result "PASS" "Configuration validation passed"
        else
            check_result "WARN" "Configuration validation found issues"
        fi
    fi
    
    echo
}

##
# Check scripts
##
check_scripts() {
    print_message "${BLUE}" "3. Checking Deployment Scripts"
    print_message "${BLUE}" "=============================="
    
    local scripts=(
        "scripts/production_setup.sh"
        "scripts/production_migration.sh"
        "scripts/deploy_production.sh"
        "scripts/validate_production.sh"
        "scripts/security_hardening.sh"
        "scripts/setup_cron.sh"
        "scripts/setup_backups.sh"
    )
    
    for script in "${scripts[@]}"; do
        local full_path="${PROJECT_ROOT}/${script}"
        
        if [[ -f "${full_path}" && -x "${full_path}" ]]; then
            if bash -n "${full_path}" > /dev/null 2>&1; then
                check_result "PASS" "${script} (syntax OK)"
            else
                check_result "FAIL" "${script} (syntax ERROR)"
            fi
        else
            check_result "FAIL" "${script} (missing or not executable)"
        fi
    done
    
    echo
}

##
# Check monitoring scripts
##
check_monitoring_scripts() {
    print_message "${BLUE}" "4. Checking Monitoring Scripts"
    print_message "${BLUE}" "==============================="
    
    local scripts=(
        "bin/monitor/monitorIngestion.sh"
        "bin/monitor/monitorAnalytics.sh"
        "bin/monitor/monitorWMS.sh"
        "bin/monitor/monitorInfrastructure.sh"
        "bin/monitor/monitorData.sh"
    )
    
    local found=0
    for script in "${scripts[@]}"; do
        local full_path="${PROJECT_ROOT}/${script}"
        
        if [[ -f "${full_path}" && -x "${full_path}" ]]; then
            if bash -n "${full_path}" > /dev/null 2>&1; then
                check_result "PASS" "${script} (syntax OK)"
                ((found++))
            else
                check_result "FAIL" "${script} (syntax ERROR)"
            fi
        else
            check_result "WARN" "${script} (missing or not executable)"
        fi
    done
    
    if [[ ${found} -eq 0 ]]; then
        check_result "FAIL" "No monitoring scripts found"
    fi
    
    echo
}

##
# Check database setup
##
check_database() {
    print_message "${BLUE}" "5. Checking Database Setup"
    print_message "${BLUE}" "=========================="
    
    # Source properties to get database name
    local dbname="notes_monitoring"
    if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
        # shellcheck disable=SC1091
        source "${PROJECT_ROOT}/etc/properties.sh" 2>/dev/null || true
        dbname="${DBNAME:-${dbname}}"
    fi
    
    # Check connection
    if psql -d "${dbname}" -c "SELECT 1;" > /dev/null 2>&1; then
        check_result "PASS" "Database connection successful (${dbname})"
        
        # Check schema
        local table_count
        table_count=$(psql -d "${dbname}" -t -A -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
        if [[ "${table_count}" -gt 0 ]]; then
            check_result "PASS" "Database schema exists (${table_count} tables)"
        else
            check_result "WARN" "Database schema not initialized"
        fi
    else
        check_result "WARN" "Database connection failed (will be created during setup)"
    fi
    
    # Check migration script
    if [[ -f "${PROJECT_ROOT}/sql/migrations/run_migrations.sh" ]]; then
        check_result "PASS" "Migration script exists"
    else
        check_result "FAIL" "Migration script missing"
    fi
    
    # Check backup script
    if [[ -f "${PROJECT_ROOT}/sql/backups/backup_database.sh" ]]; then
        check_result "PASS" "Backup script exists"
    else
        check_result "FAIL" "Backup script missing"
    fi
    
    echo
}

##
# Check security
##
check_security() {
    print_message "${BLUE}" "6. Checking Security"
    print_message "${BLUE}" "==================="
    
    # Check file permissions
    local world_writable
    world_writable=$(find "${PROJECT_ROOT}/bin" -type f -perm -002 2>/dev/null | wc -l)
    if [[ "${world_writable}" -eq 0 ]]; then
        check_result "PASS" "No world-writable files found"
    else
        check_result "WARN" "Found ${world_writable} world-writable files"
    fi
    
    # Check for hardcoded credentials
    if grep -r "password.*=.*['\"].*[^example|test|dummy]" "${PROJECT_ROOT}/bin" "${PROJECT_ROOT}/config" --exclude="*.example" 2>/dev/null | grep -v "example\|test\|dummy" > /dev/null; then
        check_result "WARN" "Potential hardcoded credentials found (review manually)"
    else
        check_result "PASS" "No obvious hardcoded credentials"
    fi
    
    # Check security audit script
    if [[ -f "${PROJECT_ROOT}/scripts/security_audit.sh" ]]; then
        check_result "PASS" "Security audit script exists"
    else
        check_result "WARN" "Security audit script missing"
    fi
    
    echo
}

##
# Check documentation
##
check_documentation() {
    print_message "${BLUE}" "7. Checking Documentation"
    print_message "${BLUE}" "========================="
    
    local docs=(
        "docs/DEPLOYMENT_GUIDE.md"
        "docs/MIGRATION_GUIDE.md"
        "docs/OPERATIONS_RUNBOOK.md"
        "docs/PRODUCTION_TROUBLESHOOTING_GUIDE.md"
        "README.md"
    )
    
    for doc in "${docs[@]}"; do
        if [[ -f "${PROJECT_ROOT}/${doc}" ]]; then
            check_result "PASS" "${doc} exists"
        else
            check_result "WARN" "${doc} missing"
        fi
    done
    
    echo
}

##
# Check system resources
##
check_resources() {
    print_message "${BLUE}" "8. Checking System Resources"
    print_message "${BLUE}" "============================"
    
    # Check disk space
    local available_space
    available_space=$(df -BG "${PROJECT_ROOT}" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ "${available_space}" -ge 1 ]]; then
        check_result "PASS" "Disk space: ${available_space}GB available"
    else
        check_result "WARN" "Low disk space: ${available_space}GB available"
    fi
    
    # Check memory
    if command -v free > /dev/null 2>&1; then
        local available_mem
        available_mem=$(free -g | awk '/^Mem:/{print $7}')
        if [[ "${available_mem}" -ge 1 ]]; then
            check_result "PASS" "Memory: ${available_mem}GB available"
        else
            check_result "WARN" "Low memory: ${available_mem}GB available"
        fi
    fi
    
    # Check log directory
    local log_dir="/var/log/osm-notes-monitoring"
    if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
        # shellcheck disable=SC1091
        source "${PROJECT_ROOT}/etc/properties.sh" 2>/dev/null || true
        log_dir="${LOG_DIR:-${log_dir}}"
    fi
    
    if [[ -d "${log_dir}" && -w "${log_dir}" ]]; then
        check_result "PASS" "Log directory exists and is writable: ${log_dir}"
    elif [[ -w "$(dirname "${log_dir}")" ]]; then
        check_result "WARN" "Log directory will be created: ${log_dir}"
    else
        check_result "FAIL" "Cannot create log directory: ${log_dir}"
    fi
    
    echo
}

##
# Generate summary
##
generate_summary() {
    echo
    print_message "${BLUE}" "Pre-Deployment Checklist Summary"
    print_message "${BLUE}" "================================="
    echo
    
    local total=$((CHECKS_PASSED + CHECKS_WARNINGS + CHECKS_FAILED))
    
    print_message "${GREEN}" "Passed: ${CHECKS_PASSED}/${total}"
    print_message "${YELLOW}" "Warnings: ${CHECKS_WARNINGS}/${total}"
    print_message "${RED}" "Failed: ${CHECKS_FAILED}/${total}"
    echo
    
    if [[ ${CHECKS_FAILED} -eq 0 ]]; then
        if [[ ${CHECKS_WARNINGS} -eq 0 ]]; then
            print_message "${GREEN}" "✓ All checks passed! Ready for production deployment."
            echo
            print_message "${BLUE}" "Next steps:"
            echo "  1. Review configuration: ./scripts/configure_production.sh --review"
            echo "  2. Run deployment: ./scripts/deploy_production.sh"
            return 0
        else
            print_message "${YELLOW}" "⚠ Checks passed with warnings. Review warnings before deployment."
            echo
            print_message "${BLUE}" "Recommended actions:"
            echo "  1. Fix warnings if critical"
            echo "  2. Review configuration: ./scripts/configure_production.sh --review"
            echo "  3. Run deployment: ./scripts/deploy_production.sh"
            return 0
        fi
    else
        print_message "${RED}" "✗ Some checks failed. Fix issues before deployment."
        echo
        print_message "${BLUE}" "Required actions:"
        echo "  1. Fix failed checks above"
        echo "  2. Re-run checklist: $0"
        echo "  3. Proceed with deployment only after all checks pass"
        return 1
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "Pre-Deployment Checklist"
    print_message "${BLUE}" "========================="
    echo
    print_message "${BLUE}" "This checklist verifies everything is ready for production deployment."
    echo
    
    check_prerequisites || true
    check_configuration || true
    check_scripts || true
    check_monitoring_scripts || true
    check_database || true
    check_security || true
    check_documentation || true
    check_resources || true
    
    generate_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
