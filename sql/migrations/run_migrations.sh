#!/usr/bin/env bash
#
# Database Migration Runner
# Runs pending database migrations in order
#
# Version: 1.0.0
# Date: 2025-12-24
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly MIGRATIONS_DIR="${SCRIPT_DIR}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Default database name
DBNAME="${DBNAME:-osm_notes_monitoring}"

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
Usage: $0 [OPTIONS] [MIGRATION_FILE]

Run database migrations for OSM-Notes-Monitoring.

Options:
    -d, --database DATABASE    Database name (default: osm_notes_monitoring)
    -l, --list                 List pending migrations
    -v, --verbose              Verbose output
    -h, --help                 Show this help message

Arguments:
    MIGRATION_FILE             Run specific migration file (optional)

Examples:
    $0                         # Run all pending migrations
    $0 -d osm_notes_monitoring_test  # Run on test database
    $0 20251224_120000_add_column.sql  # Run specific migration
    $0 --list                  # List pending migrations

EOF
}

##
# Initialize migration tracking table
##
init_migration_table() {
    local dbname="${1}"
    
    psql -d "${dbname}" << 'EOF' > /dev/null 2>&1 || true
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);
EOF
}

##
# Get applied migrations
##
get_applied_migrations() {
    local dbname="${1}"
    
    psql -d "${dbname}" -t -A -c \
        "SELECT version FROM schema_migrations ORDER BY version;" 2>/dev/null || echo ""
}

##
# Get all migration files
##
get_migration_files() {
    find "${MIGRATIONS_DIR}" -maxdepth 1 -name "*.sql" -type f \
        ! -name "README.md" \
        ! -name "*_rollback.sql" \
        | sort
}

##
# Get pending migrations
##
get_pending_migrations() {
    local dbname="${1}"
    local applied
    applied=$(get_applied_migrations "${dbname}")
    
    while IFS= read -r migration_file; do
        local migration_name
        migration_name=$(basename "${migration_file}")
        
        # Check if migration is already applied
        if ! echo "${applied}" | grep -q "^${migration_name}$"; then
            echo "${migration_file}"
        fi
    done < <(get_migration_files)
}

##
# Record migration as applied
##
record_migration() {
    local dbname="${1}"
    local migration_file="${2}"
    local migration_name
    migration_name=$(basename "${migration_file}")
    
    # Extract description from migration file (first comment line)
    local description
    description=$(grep -m 1 "^-- Description:" "${migration_file}" | sed 's/-- Description: //' || echo "")
    
    psql -d "${dbname}" -c \
        "INSERT INTO schema_migrations (version, description) VALUES ('${migration_name}', '${description}') ON CONFLICT (version) DO NOTHING;" \
        > /dev/null 2>&1
}

##
# Run a single migration
##
run_migration() {
    local dbname="${1}"
    local migration_file="${2}"
    local verbose="${3:-false}"
    local migration_name
    migration_name=$(basename "${migration_file}")
    
    print_message "${BLUE}" "Running migration: ${migration_name}"
    
    if [[ "${verbose}" == "true" ]]; then
        if psql -d "${dbname}" -f "${migration_file}"; then
            record_migration "${dbname}" "${migration_file}"
            print_message "${GREEN}" "  ✓ Migration applied successfully"
            return 0
        else
            print_message "${RED}" "  ✗ Migration failed"
            return 1
        fi
    else
        if psql -d "${dbname}" -f "${migration_file}" > /dev/null 2>&1; then
            record_migration "${dbname}" "${migration_file}"
            print_message "${GREEN}" "  ✓ Migration applied successfully"
            return 0
        else
            print_message "${RED}" "  ✗ Migration failed (run with -v for details)"
            return 1
        fi
    fi
}

##
# List pending migrations
##
list_pending_migrations() {
    local dbname="${1}"
    local pending
    pending=$(get_pending_migrations "${dbname}")
    
    if [[ -z "${pending}" ]]; then
        print_message "${GREEN}" "No pending migrations"
        return 0
    fi
    
    print_message "${BLUE}" "Pending migrations:"
    while IFS= read -r migration_file; do
        local migration_name
        migration_name=$(basename "${migration_file}")
        echo "  - ${migration_name}"
    done <<< "${pending}"
}

##
# Main
##
main() {
    local verbose=false
    local list_only=false
    local specific_migration=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -d|--database)
                DBNAME="${2}"
                shift 2
                ;;
            -l|--list)
                list_only=true
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
                specific_migration="${1}"
                shift
                ;;
        esac
    done
    
    # Check database connection
    if ! psql -d "${DBNAME}" -c "SELECT 1;" > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: Cannot connect to database: ${DBNAME}"
        exit 1
    fi
    
    # Initialize migration tracking
    init_migration_table "${DBNAME}"
    
    # List only mode
    if [[ "${list_only}" == "true" ]]; then
        list_pending_migrations "${DBNAME}"
        exit 0
    fi
    
    # Run specific migration
    if [[ -n "${specific_migration}" ]]; then
        local migration_file="${MIGRATIONS_DIR}/${specific_migration}"
        if [[ ! -f "${migration_file}" ]]; then
            print_message "${RED}" "Migration file not found: ${migration_file}"
            exit 1
        fi
        
        if run_migration "${DBNAME}" "${migration_file}" "${verbose}"; then
            exit 0
        else
            exit 1
        fi
    fi
    
    # Run all pending migrations
    local pending
    pending=$(get_pending_migrations "${DBNAME}")
    
    if [[ -z "${pending}" ]]; then
        print_message "${GREEN}" "No pending migrations"
        exit 0
    fi
    
    print_message "${BLUE}" "Running pending migrations on database: ${DBNAME}"
    echo
    
    local failed=0
    while IFS= read -r migration_file; do
        if ! run_migration "${DBNAME}" "${migration_file}" "${verbose}"; then
            failed=$((failed + 1))
            print_message "${RED}" "Stopping migration process due to failure"
            break
        fi
    done <<< "${pending}"
    
    echo
    if [[ ${failed} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All migrations applied successfully"
        exit 0
    else
        print_message "${RED}" "✗ Migration process failed"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

