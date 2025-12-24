#!/usr/bin/env bash
#
# Database Restore Script
# Restores a backup of the OSM-Notes-Monitoring database
#
# Version: 1.0.0
# Date: 2025-12-24
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Default values
DBNAME="${DBNAME:-osm_notes_monitoring}"
BACKUP_DIR="${BACKUP_DIR:-${SCRIPT_DIR}}"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Print usage
##
usage() {
    cat << EOF
Usage: $0 [OPTIONS] BACKUP_FILE

Restore a backup of the OSM-Notes-Monitoring database.

Options:
    -d, --database DATABASE    Target database name (default: osm_notes_monitoring)
    -f, --force                 Force restore (drop existing database)
    -v, --verbose               Verbose output
    -h, --help                  Show this help message

Arguments:
    BACKUP_FILE                 Backup file to restore (.sql or .sql.gz)

Examples:
    $0 backup.sql               # Restore from backup.sql
    $0 -d test_db backup.sql.gz # Restore to test_db database
    $0 -f backup.sql            # Force restore (drop existing database)

WARNING: This will overwrite the target database!

EOF
}

##
# Check prerequisites
##
check_prerequisites() {
    if ! command -v psql > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: psql not found. Please install PostgreSQL client tools."
        exit 1
    fi
    
    if ! psql -lqt > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: Cannot connect to PostgreSQL. Check your connection."
        exit 1
    fi
}

##
# Check if backup file exists
##
check_backup_file() {
    local backup_file="${1}"
    
    if [[ ! -f "${backup_file}" ]]; then
        print_message "${RED}" "ERROR: Backup file not found: ${backup_file}"
        exit 1
    fi
    
    # Check if file is readable
    if [[ ! -r "${backup_file}" ]]; then
        print_message "${RED}" "ERROR: Cannot read backup file: ${backup_file}"
        exit 1
    fi
}

##
# Check if database exists
##
database_exists() {
    local dbname="${1}"
    
    psql -lqt | cut -d \| -f 1 | grep -qw "${dbname}"
}

##
# Drop database if exists
##
drop_database() {
    local dbname="${1}"
    local force="${2:-false}"
    
    if database_exists "${dbname}"; then
        if [[ "${force}" == "true" ]]; then
            print_message "${YELLOW}" "Dropping existing database: ${dbname}"
            if dropdb "${dbname}"; then
                print_message "${GREEN}" "✓ Database dropped"
                return 0
            else
                print_message "${RED}" "✗ Failed to drop database"
                return 1
            fi
        else
            print_message "${RED}" "ERROR: Database ${dbname} already exists."
            print_message "${YELLOW}" "Use -f/--force to drop and recreate it."
            return 1
        fi
    fi
    
    return 0
}

##
# Create database
##
create_database() {
    local dbname="${1}"
    
    if ! database_exists "${dbname}"; then
        print_message "${BLUE}" "Creating database: ${dbname}"
        if createdb "${dbname}"; then
            print_message "${GREEN}" "✓ Database created"
            return 0
        else
            print_message "${RED}" "✗ Failed to create database"
            return 1
        fi
    fi
    
    return 0
}

##
# Restore backup
##
restore_backup() {
    local backup_file="${1}"
    local dbname="${2}"
    local verbose="${3:-false}"
    
    print_message "${BLUE}" "Restoring backup: ${backup_file}"
    print_message "${BLUE}" "Target database: ${dbname}"
    
    local psql_opts=("-d" "${dbname}")
    
    if [[ "${verbose}" == "true" ]]; then
        psql_opts+=("-v" "ON_ERROR_STOP=1")
    else
        psql_opts+=("-q")
    fi
    
    # Check if backup is compressed
    if [[ "${backup_file}" == *.gz ]]; then
        print_message "${BLUE}" "Decompressing and restoring..."
        if gunzip -c "${backup_file}" | psql "${psql_opts[@]}"; then
            print_message "${GREEN}" "✓ Backup restored successfully"
            return 0
        else
            print_message "${RED}" "✗ Restore failed"
            return 1
        fi
    else
        print_message "${BLUE}" "Restoring..."
        if psql "${psql_opts[@]}" -f "${backup_file}"; then
            print_message "${GREEN}" "✓ Backup restored successfully"
            return 0
        else
            print_message "${RED}" "✗ Restore failed"
            return 1
        fi
    fi
}

##
# Main
##
main() {
    local force=false
    local verbose=false
    local backup_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -d|--database)
                DBNAME="${2}"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                print_message "${RED}" "Unknown option: ${1}"
                usage
                exit 1
                ;;
            *)
                if [[ -z "${backup_file}" ]]; then
                    backup_file="${1}"
                else
                    print_message "${RED}" "Unexpected argument: ${1}"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check if backup file was provided
    if [[ -z "${backup_file}" ]]; then
        print_message "${RED}" "ERROR: Backup file required"
        usage
        exit 1
    fi
    
    # Resolve full path if relative
    if [[ ! "${backup_file}" =~ ^/ ]]; then
        backup_file="${BACKUP_DIR}/${backup_file}"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check backup file
    check_backup_file "${backup_file}"
    
    # Warning
    print_message "${YELLOW}" "WARNING: This will overwrite database: ${DBNAME}"
    if [[ "${force}" != "true" ]]; then
        print_message "${YELLOW}" "Press Ctrl+C to cancel, or use -f/--force to proceed"
        sleep 3
    fi
    
    # Drop database if exists and force
    if ! drop_database "${DBNAME}" "${force}"; then
        exit 1
    fi
    
    # Create database
    if ! create_database "${DBNAME}"; then
        exit 1
    fi
    
    # Restore backup
    if restore_backup "${backup_file}" "${DBNAME}" "${verbose}"; then
        print_message "${GREEN}" "✓ Database restore completed successfully"
        exit 0
    else
        print_message "${RED}" "✗ Database restore failed"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

