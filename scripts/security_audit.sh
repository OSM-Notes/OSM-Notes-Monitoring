#!/usr/bin/env bash
#
# Security Audit Script
# Performs comprehensive security audit of the monitoring system
#
# Version: 1.0.0
# Date: 2025-12-31
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

# Source libraries
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/bin/lib/configFunctions.sh" ]]; then
    source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
fi
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh" ]]; then
    source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
fi

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Audit results
AUDIT_ISSUES=0
AUDIT_WARNINGS=0
AUDIT_PASSED=0

# Output file
OUTPUT_FILE="${OUTPUT_FILE:-${PROJECT_ROOT}/reports/security_audit_$(date +%Y%m%d_%H%M%S).txt}"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Record audit issue
##
record_issue() {
    local severity="${1}"
    local message="${2}"
    
    if [[ "${severity}" == "CRITICAL" ]] || [[ "${severity}" == "HIGH" ]]; then
        ((AUDIT_ISSUES++))
        print_message "${RED}" "  ✗ [${severity}] ${message}"
    elif [[ "${severity}" == "MEDIUM" ]] || [[ "${severity}" == "LOW" ]]; then
        ((AUDIT_WARNINGS++))
        print_message "${YELLOW}" "  ⚠ [${severity}] ${message}"
    fi
}

##
# Record passed check
##
record_pass() {
    local message="${1}"
    ((AUDIT_PASSED++))
    print_message "${GREEN}" "  ✓ ${message}"
}

##
# Check file permissions
##
check_file_permissions() {
    print_message "${BLUE}" "Checking file permissions..."
    
    local issues=0
    
    # Check for world-writable files
    while IFS= read -r file; do
        if [[ -f "${file}" ]]; then
            local perms
            perms=$(stat -c "%a" "${file}" 2>/dev/null || stat -f "%OLp" "${file}" 2>/dev/null || echo "")
            if [[ "${perms}" =~ [2367]$ ]]; then
                record_issue "MEDIUM" "World-writable file: ${file} (perms: ${perms})"
                ((issues++))
            fi
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" 2>/dev/null)
    
    # Check for files with execute bit but not readable
    while IFS= read -r file; do
        if [[ -f "${file}" ]] && [[ ! -r "${file}" ]]; then
            record_issue "LOW" "Executable but not readable: ${file}"
            ((issues++))
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -executable 2>/dev/null)
    
    if [[ ${issues} -eq 0 ]]; then
        record_pass "File permissions are secure"
    fi
}

##
# Check for SQL injection vulnerabilities
##
check_sql_injection() {
    print_message "${BLUE}" "Checking for SQL injection vulnerabilities..."
    
    local issues=0
    
    # Check for direct variable interpolation in SQL queries
    while IFS= read -r file; do
        if grep -n "VALUES.*\${.*}" "${file}" 2>/dev/null | grep -v "::jsonb\|::inet\|::numeric" > /dev/null; then
            record_issue "HIGH" "Potential SQL injection in ${file}: Direct variable interpolation in SQL"
            ((issues++))
        fi
        
        # Check for psql -c with variables
        if grep -n "psql.*-c.*\${" "${file}" 2>/dev/null | grep -v "#.*SQL" > /dev/null; then
            local line
            line=$(grep -n "psql.*-c.*\${" "${file}" 2>/dev/null | head -1 | cut -d: -f1)
            record_issue "HIGH" "Potential SQL injection in ${file}:${line}: Direct variable in psql -c"
            ((issues++))
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" 2>/dev/null)
    
    if [[ ${issues} -eq 0 ]]; then
        record_pass "No obvious SQL injection vulnerabilities found"
    fi
}

##
# Check for command injection vulnerabilities
##
check_command_injection() {
    print_message "${BLUE}" "Checking for command injection vulnerabilities..."
    
    local issues=0
    
    # Check for eval usage
    while IFS= read -r file; do
        if grep -n "eval " "${file}" 2>/dev/null | grep -v "#.*eval" > /dev/null; then
            local line
            line=$(grep -n "eval " "${file}" 2>/dev/null | head -1 | cut -d: -f1)
            record_issue "HIGH" "Command injection risk in ${file}:${line}: Use of 'eval'"
            ((issues++))
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" 2>/dev/null)
    
    # Check for unquoted variables in command substitution
    # shellcheck disable=SC2016  # Intentionally using single quotes to search for literal $(
    while IFS= read -r file; do
        if grep -n '\$(' "${file}" 2>/dev/null | grep -v "\"\$(" | grep -v "''\$(" > /dev/null; then
            # This is a heuristic - may have false positives
            local suspicious
            # shellcheck disable=SC2016  # Intentionally using single quotes to search for literal $(
            suspicious=$(grep -n '\$(' "${file}" 2>/dev/null | grep -v "\"\$(" | grep -v "''\$(" | head -1 || true)
            if [[ -n "${suspicious}" ]]; then
                record_issue "MEDIUM" "Potential command injection in ${file}: Unquoted command substitution"
                ((issues++))
            fi
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" 2>/dev/null)
    
    if [[ ${issues} -eq 0 ]]; then
        record_pass "No obvious command injection vulnerabilities found"
    fi
}

##
# Check for path traversal vulnerabilities
##
check_path_traversal() {
    print_message "${BLUE}" "Checking for path traversal vulnerabilities..."
    
    local issues=0
    
    # Check for file operations with user input
    # shellcheck disable=SC2016  # Intentionally using single quotes to search for literal ${ pattern
    while IFS= read -r file; do
        if grep -n "cat\|rm\|mv\|cp\|chmod\|chown" "${file}" 2>/dev/null | grep -E '\$\{|"\${' > /dev/null; then
            # Check if input is validated
            if ! grep -q "validate\|sanitize\|basename\|realpath" "${file}" 2>/dev/null; then
                record_issue "MEDIUM" "Potential path traversal in ${file}: File operations with user input"
                ((issues++))
            fi
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" 2>/dev/null)
    
    if [[ ${issues} -eq 0 ]]; then
        record_pass "No obvious path traversal vulnerabilities found"
    fi
}

##
# Check input validation
##
check_input_validation() {
    print_message "${BLUE}" "Checking input validation..."
    
    local issues=0
    
    # Check security functions for input validation
    local security_file="${PROJECT_ROOT}/bin/lib/securityFunctions.sh"
    if [[ -f "${security_file}" ]]; then
        # Check IP validation
        if ! grep -q "validate_ip\|is_valid_ip" "${security_file}" 2>/dev/null; then
            record_issue "MEDIUM" "IP validation function not found in securityFunctions.sh"
            ((issues++))
        fi
        
        # Check if functions validate input
        while IFS= read -r func; do
            if ! grep -A 10 "^${func}()" "${security_file}" 2>/dev/null | grep -q "validate\|check\|sanitize"; then
                record_issue "LOW" "Function ${func} may not validate input"
                ((issues++))
            fi
        done < <(grep "^[a-z_]*()" "${security_file}" 2>/dev/null | sed 's/().*//')
    fi
    
    if [[ ${issues} -eq 0 ]]; then
        record_pass "Input validation appears adequate"
    fi
}

##
# Check for hardcoded credentials
##
check_hardcoded_credentials() {
    print_message "${BLUE}" "Checking for hardcoded credentials..."
    
    local issues=0
    
    # Check for common password patterns
    while IFS= read -r file; do
        if grep -iE "password\s*=\s*['\"][^'\"]{6,}" "${file}" 2>/dev/null | grep -v "example\|test\|dummy\|changeme" > /dev/null; then
            record_issue "CRITICAL" "Potential hardcoded password in ${file}"
            ((issues++))
        fi
        
        # Check for API keys
        if grep -iE "(api[_-]?key|secret|token)\s*=\s*['\"][^'\"]{10,}" "${file}" 2>/dev/null | grep -v "example\|test\|dummy" > /dev/null; then
            record_issue "HIGH" "Potential hardcoded API key/secret in ${file}"
            ((issues++))
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" 2>/dev/null)
    
    # Check config files (but allow .example files)
    while IFS= read -r file; do
        if [[ "${file}" != *.example ]] && [[ "${file}" != *.example.* ]]; then
            if grep -iE "password\s*=\s*['\"][^'\"]{6,}" "${file}" 2>/dev/null | grep -v "example\|test\|dummy\|changeme" > /dev/null; then
                record_issue "CRITICAL" "Potential hardcoded password in config: ${file}"
                ((issues++))
            fi
        fi
    done < <(find "${PROJECT_ROOT}/config" -type f 2>/dev/null)
    
    if [[ ${issues} -eq 0 ]]; then
        record_pass "No hardcoded credentials found"
    fi
}

##
# Check error handling
##
check_error_handling() {
    print_message "${BLUE}" "Checking error handling..."
    
    local issues=0
    
    # Check for scripts without set -euo pipefail
    while IFS= read -r file; do
        if ! grep -q "set -euo pipefail\|set -eu\|set -e" "${file}" 2>/dev/null; then
            record_issue "MEDIUM" "Script ${file} may not handle errors properly (missing 'set -e')"
            ((issues++))
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" -executable 2>/dev/null)
    
    # Check for unhandled command failures
    while IFS= read -r file; do
        if grep -n "psql\|curl\|wget" "${file}" 2>/dev/null | grep -v "if\|||\|&&" > /dev/null; then
            local suspicious
            suspicious=$(grep -n "psql\|curl\|wget" "${file}" 2>/dev/null | grep -v "if\|||\|&&" | head -1 || true)
            if [[ -n "${suspicious}" ]]; then
                record_issue "LOW" "Unhandled command failure possible in ${file}"
                ((issues++))
            fi
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" 2>/dev/null)
    
    if [[ ${issues} -eq 0 ]]; then
        record_pass "Error handling appears adequate"
    fi
}

##
# Check logging of sensitive data
##
check_sensitive_logging() {
    print_message "${BLUE}" "Checking for sensitive data in logs..."
    
    local issues=0
    
    # Check for password logging
    while IFS= read -r file; do
        if grep -iE "log.*password\|echo.*password" "${file}" 2>/dev/null | grep -v "#.*password" > /dev/null; then
            record_issue "HIGH" "Potential password logging in ${file}"
            ((issues++))
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" 2>/dev/null)
    
    if [[ ${issues} -eq 0 ]]; then
        record_pass "No obvious sensitive data logging found"
    fi
}

##
# Check security configuration
##
check_security_config() {
    print_message "${BLUE}" "Checking security configuration..."
    
    local issues=0
    
    # Check if security.conf.example exists
    if [[ ! -f "${PROJECT_ROOT}/config/security.conf.example" ]]; then
        record_issue "MEDIUM" "Security configuration template not found"
        ((issues++))
    fi
    
    # Check if properties.sh has secure defaults
    local properties_file="${PROJECT_ROOT}/etc/properties.sh"
    if [[ -f "${properties_file}" ]]; then
        if grep -q "DBPASSWORD\|PGPASSWORD" "${properties_file}" 2>/dev/null && ! grep -q "example\|test\|changeme" "${properties_file}" 2>/dev/null; then
            record_issue "HIGH" "Database password may be hardcoded in ${properties_file}"
            ((issues++))
        fi
    fi
    
    if [[ ${issues} -eq 0 ]]; then
        record_pass "Security configuration appears secure"
    fi
}

##
# Check shellcheck compliance
##
check_shellcheck() {
    print_message "${BLUE}" "Checking shellcheck compliance..."
    
    if ! command -v shellcheck > /dev/null 2>&1; then
        record_issue "LOW" "shellcheck not installed - cannot perform static analysis"
        return
    fi
    
    local issues=0
    local checked=0
    
    while IFS= read -r file; do
        ((checked++))
        if ! shellcheck -f gcc "${file}" > /dev/null 2>&1; then
            local sc_errors
            sc_errors=$(shellcheck -f gcc "${file}" 2>&1 | grep -c "error:" || echo "0")
            if [[ "${sc_errors}" -gt 0 ]]; then
                record_issue "MEDIUM" "shellcheck found ${sc_errors} error(s) in ${file}"
                ((issues++))
            fi
        fi
    done < <(find "${PROJECT_ROOT}/bin" -type f -name "*.sh" 2>/dev/null)
    
    if [[ ${issues} -eq 0 ]] && [[ ${checked} -gt 0 ]]; then
        record_pass "All ${checked} scripts pass shellcheck"
    fi
}

##
# Generate summary
##
generate_summary() {
    echo ""
    print_message "${BLUE}" "=========================================="
    print_message "${GREEN}" "Security Audit Summary"
    print_message "${BLUE}" "=========================================="
    echo ""
    
    print_message "${GREEN}" "Passed: ${AUDIT_PASSED}"
    print_message "${YELLOW}" "Warnings: ${AUDIT_WARNINGS}"
    print_message "${RED}" "Issues: ${AUDIT_ISSUES}"
    echo ""
    
    if [[ ${AUDIT_ISSUES} -eq 0 ]] && [[ ${AUDIT_WARNINGS} -eq 0 ]]; then
        print_message "${GREEN}" "✓ Security audit passed!"
        return 0
    elif [[ ${AUDIT_ISSUES} -eq 0 ]]; then
        print_message "${YELLOW}" "⚠ Security audit passed with warnings"
        return 0
    else
        print_message "${RED}" "✗ Security audit found issues that need attention"
        return 1
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "Security Audit for OSM-Notes-Monitoring"
    print_message "${BLUE}" "=========================================="
    echo ""
    
    # Create output directory
    mkdir -p "$(dirname "${OUTPUT_FILE}")"
    
    # Run all checks
    {
        echo "Security Audit Report"
        echo "Generated: $(date)"
        echo "Project: ${PROJECT_ROOT}"
        echo "=========================================="
        echo ""
        
        check_file_permissions
        echo ""
        
        check_sql_injection
        echo ""
        
        check_command_injection
        echo ""
        
        check_path_traversal
        echo ""
        
        check_input_validation
        echo ""
        
        check_hardcoded_credentials
        echo ""
        
        check_error_handling
        echo ""
        
        check_sensitive_logging
        echo ""
        
        check_security_config
        echo ""
        
        check_shellcheck
        echo ""
        
        generate_summary
        
    } | tee "${OUTPUT_FILE}"
    
    print_message "${BLUE}" ""
    print_message "${BLUE}" "Report saved to: ${OUTPUT_FILE}"
    
    # Return exit code based on issues found
    if [[ ${AUDIT_ISSUES} -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
