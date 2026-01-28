#!/usr/bin/env bash
#
# Query Performance Analysis Script
# Analyzes query performance and provides optimization recommendations
#
# Version: 1.0.0
# Date: 2025-12-31
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

# Source configuration
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
    source "${PROJECT_ROOT}/etc/properties.sh"
fi

# Source libraries
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/bin/lib/configFunctions.sh" ]]; then
    source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
fi
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh" ]]; then
    source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
fi
# shellcheck disable=SC1091
if [[ -f "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh" ]]; then
    source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
fi

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Default values
DBNAME="${DBNAME:-osm_notes_monitoring}"
DBHOST="${DBHOST:-localhost}"
DBPORT="${DBPORT:-5432}"
DBUSER="${DBUSER:-postgres}"
OUTPUT_FILE="${OUTPUT_FILE:-${PROJECT_ROOT}/reports/query_performance_analysis_$(date +%Y%m%d_%H%M%S).txt}"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check if database is accessible
##
check_database() {
    if ! check_database_connection; then
        print_message "${RED}" "Error: Cannot connect to database"
        print_message "${YELLOW}" "  Host: ${DBHOST}"
        print_message "${YELLOW}" "  Port: ${DBPORT}"
        print_message "${YELLOW}" "  User: ${DBUSER}"
        print_message "${YELLOW}" "  Database: ${DBNAME}"
        exit 1
    fi
}

##
# Analyze index usage
##
analyze_index_usage() {
    print_message "${BLUE}" "Analyzing index usage..."

    local query
    query="SELECT
        schemaname,
        tablename,
        indexname,
        idx_scan AS index_scans,
        pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
    FROM pg_stat_user_indexes
    WHERE schemaname = 'public'
      AND idx_scan = 0
    ORDER BY pg_relation_size(indexrelid) DESC;"

    local unused_indexes
    unused_indexes=$(execute_sql_query "${query}" 2>/dev/null || echo "")

    if [[ -n "${unused_indexes}" ]]; then
        print_message "${YELLOW}" "Unused indexes found:"
        echo "${unused_indexes}"
        echo ""
    else
        print_message "${GREEN}" "No unused indexes found"
    fi
}

##
# Analyze table bloat
##
analyze_table_bloat() {
    print_message "${BLUE}" "Analyzing table bloat..."

    local query
    query="SELECT
        schemaname,
        tablename,
        n_live_tup AS live_tuples,
        n_dead_tup AS dead_tuples,
        ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_percent,
        last_vacuum,
        last_autovacuum
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
      AND n_dead_tup > 1000
    ORDER BY n_dead_tup DESC;"

    local bloat_info
    bloat_info=$(execute_sql_query "${query}" 2>/dev/null || echo "")

    if [[ -n "${bloat_info}" ]]; then
        print_message "${YELLOW}" "Tables with significant bloat (>1000 dead tuples):"
        echo "${bloat_info}"
        echo ""
    else
        print_message "${GREEN}" "No significant table bloat found"
    fi
}

##
# Analyze sequential scans
##
analyze_sequential_scans() {
    print_message "${BLUE}" "Analyzing sequential scans..."

    local query
    query="SELECT
        schemaname,
        tablename,
        seq_scan AS sequential_scans,
        idx_scan AS index_scans,
        ROUND(seq_scan * 100.0 / NULLIF(seq_scan + idx_scan, 0), 2) AS seq_scan_percent,
        n_live_tup AS live_tuples
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
      AND seq_scan > 100
    ORDER BY seq_scan DESC;"

    local seq_scans
    seq_scans=$(execute_sql_query "${query}" 2>/dev/null || echo "")

    if [[ -n "${seq_scans}" ]]; then
        print_message "${YELLOW}" "Tables with high sequential scan ratio (>100 scans):"
        echo "${seq_scans}"
        echo ""
    else
        print_message "${GREEN}" "No tables with excessive sequential scans found"
    fi
}

##
# Analyze index sizes
##
analyze_index_sizes() {
    print_message "${BLUE}" "Analyzing index sizes..."

    local query
    query="SELECT
        schemaname,
        tablename,
        indexname,
        pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
        pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size
    FROM pg_stat_user_indexes
    WHERE schemaname = 'public'
    ORDER BY pg_relation_size(indexrelid) DESC
    LIMIT 10;"

    local index_sizes
    index_sizes=$(execute_sql_query "${query}" 2>/dev/null || echo "")

    if [[ -n "${index_sizes}" ]]; then
        print_message "${BLUE}" "Top 10 largest indexes:"
        echo "${index_sizes}"
        echo ""
    fi
}

##
# Test query performance
##
test_query_performance() {
    print_message "${BLUE}" "Testing query performance..."

    # Test 1: get_latest_metric_value performance
    print_message "${BLUE}" "  Testing get_latest_metric_value query..."
    local start_time
    start_time=$(date +%s%N)

    execute_sql_query "SELECT metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'test_metric' AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour' ORDER BY timestamp DESC LIMIT 1;" > /dev/null 2>&1 || true

    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))

    if [[ ${duration_ms} -lt 100 ]]; then
        print_message "${GREEN}" "    ✓ Query completed in ${duration_ms}ms (good)"
    elif [[ ${duration_ms} -lt 500 ]]; then
        print_message "${YELLOW}" "    ⚠ Query completed in ${duration_ms}ms (acceptable)"
    else
        print_message "${RED}" "    ✗ Query completed in ${duration_ms}ms (slow)"
    fi

    # Test 2: get_metrics_summary performance
    print_message "${BLUE}" "  Testing get_metrics_summary query..."
    start_time=$(date +%s%N)

    execute_sql_query "SELECT metric_name, AVG(metric_value) as avg_value, COUNT(*) as sample_count FROM metrics WHERE component = 'ingestion' AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours' GROUP BY metric_name;" > /dev/null 2>&1 || true

    end_time=$(date +%s%N)
    duration_ms=$(( (end_time - start_time) / 1000000 ))

    if [[ ${duration_ms} -lt 500 ]]; then
        print_message "${GREEN}" "    ✓ Query completed in ${duration_ms}ms (good)"
    elif [[ ${duration_ms} -lt 2000 ]]; then
        print_message "${YELLOW}" "    ⚠ Query completed in ${duration_ms}ms (acceptable)"
    else
        print_message "${RED}" "    ✗ Query completed in ${duration_ms}ms (slow)"
    fi

    # Test 3: Active alerts query performance
    print_message "${BLUE}" "  Testing active alerts query..."
    start_time=$(date +%s%N)

    execute_sql_query "SELECT COUNT(*) FROM alerts WHERE status = 'active';" > /dev/null 2>&1 || true

    end_time=$(date +%s%N)
    duration_ms=$(( (end_time - start_time) / 1000000 ))

    if [[ ${duration_ms} -lt 50 ]]; then
        print_message "${GREEN}" "    ✓ Query completed in ${duration_ms}ms (good)"
    elif [[ ${duration_ms} -lt 200 ]]; then
        print_message "${YELLOW}" "    ⚠ Query completed in ${duration_ms}ms (acceptable)"
    else
        print_message "${RED}" "    ✗ Query completed in ${duration_ms}ms (slow)"
    fi
}

##
# Generate recommendations
##
generate_recommendations() {
    print_message "${BLUE}" "Generating optimization recommendations..."
    echo ""

    echo "=== Optimization Recommendations ==="
    echo ""
    echo "1. Run ANALYZE regularly:"
    echo "   ANALYZE metrics;"
    echo "   ANALYZE alerts;"
    echo "   ANALYZE component_health;"
    echo ""
    echo "2. Run VACUUM ANALYZE for high-write tables:"
    echo "   VACUUM ANALYZE metrics;"
    echo "   VACUUM ANALYZE alerts;"
    echo "   VACUUM ANALYZE security_events;"
    echo ""
    echo "3. Apply optimization indexes:"
    echo "   psql -d ${DBNAME} -f ${PROJECT_ROOT}/sql/optimize_queries.sql"
    echo ""
    echo "4. Monitor slow queries (if pg_stat_statements is enabled):"
    echo "   SELECT query, mean_exec_time, calls FROM pg_stat_statements"
    echo "   WHERE mean_exec_time > 1000 ORDER BY mean_exec_time DESC;"
    echo ""
}

##
# Main
##
main() {
    print_message "${GREEN}" "Query Performance Analysis"
    print_message "${BLUE}" "=========================="
    echo ""

    # Check database connection
    check_database

    # Create output directory
    mkdir -p "$(dirname "${OUTPUT_FILE}")"

    # Run analysis
    {
        echo "Query Performance Analysis Report"
        echo "Generated: $(date)"
        echo "Database: ${DBNAME}"
        echo "=========================================="
        echo ""

        analyze_index_usage
        echo ""

        analyze_table_bloat
        echo ""

        analyze_sequential_scans
        echo ""

        analyze_index_sizes
        echo ""

        test_query_performance
        echo ""

        generate_recommendations

    } | tee "${OUTPUT_FILE}"

    print_message "${GREEN}" ""
    print_message "${GREEN}" "Analysis complete!"
    print_message "${BLUE}" "Report saved to: ${OUTPUT_FILE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
