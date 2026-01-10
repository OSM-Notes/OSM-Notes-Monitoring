#!/usr/bin/env bash
#
# Datamart Metrics Collection Script
# Collects metrics from the OSM-Notes-Analytics datamart processes
#
# Version: 1.0.0
# Date: 2026-01-09
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
readonly PROJECT_ROOT

# Source libraries
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/datamartLogParser.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging only if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	init_logging "${LOG_DIR}/datamart_metrics.log" "collectDatamartMetrics"
fi

# Component name
readonly COMPONENT="ANALYTICS"

# Datamart log file patterns (allow override in test mode)
if [[ "${TEST_MODE:-false}" != "true" ]]; then
	readonly DATAMART_COUNTRIES_PATTERN="${DATAMART_COUNTRIES_PATTERN:-/tmp/datamartCountries_*/datamartCountries.log}"
	readonly DATAMART_USERS_PATTERN="${DATAMART_USERS_PATTERN:-/tmp/datamartUsers_*/datamartUsers.log}"
	readonly DATAMART_GLOBAL_PATTERN="${DATAMART_GLOBAL_PATTERN:-/tmp/datamartGlobal_*/datamartGlobal.log}"
else
	DATAMART_COUNTRIES_PATTERN="${DATAMART_COUNTRIES_PATTERN:-/tmp/datamartCountries_*/datamartCountries.log}"
	DATAMART_USERS_PATTERN="${DATAMART_USERS_PATTERN:-/tmp/datamartUsers_*/datamartUsers.log}"
	DATAMART_GLOBAL_PATTERN="${DATAMART_GLOBAL_PATTERN:-/tmp/datamartGlobal_*/datamartGlobal.log}"
fi

##
# Show usage
##
usage() {
	cat <<EOF
Datamart Metrics Collection Script

Collects metrics from the OSM-Notes-Analytics datamart processes.

Usage: $0 [OPTIONS]

Options:
    -h, --help            Show this help message

Examples:
    # Collect all datamart metrics
    $0
EOF
}

##
# Check datamart process status
##
check_datamart_process_status() {
	local datamart_name="${1:?Datamart name required}"
	local process_running=0
	local process_pid=0

	# Check if datamart process is running
	if pgrep -f "datamart${datamart_name^}.sh" >/dev/null 2>&1; then
		process_running=1
		process_pid=$(pgrep -f "datamart${datamart_name^}.sh" | head -1 || echo "0")
	fi

	record_metric "${COMPONENT}" "datamart_process_running" "${process_running}" "component=analytics,datamart=\"${datamart_name}\""
	if [[ ${process_running} -eq 1 ]]; then
		record_metric "${COMPONENT}" "datamart_process_pid" "${process_pid}" "component=analytics,datamart=\"${datamart_name}\""
		log_info "${COMPONENT}: Datamart ${datamart_name} process is running (PID: ${process_pid})"
	else
		log_info "${COMPONENT}: Datamart ${datamart_name} process is not running"
	fi

	return 0
}

##
# Collect datamart log metrics
##
collect_datamart_log_metrics() {
	log_info "${COMPONENT}: Starting datamart log analysis"

	# Parse all datamart logs using the parser library
	if parse_all_datamart_logs; then
		log_info "${COMPONENT}: Datamart log analysis completed"
		return 0
	else
		log_warning "${COMPONENT}: Datamart log analysis failed or no logs found"
		return 1
	fi
}

##
# Check datamart freshness from database
##
check_datamart_freshness() {
	log_info "${COMPONENT}: Checking datamart freshness from database"

	if ! check_database_connection; then
		log_warning "${COMPONENT}: Cannot check datamart freshness - database connection failed"
		return 1
	fi

	# Check freshness for each datamart table
	local datamarts=("datamart_countries" "datamart_users" "datamart_global")

	for datamart in "${datamarts[@]}"; do
		local query="SELECT EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint AS freshness_seconds FROM dwh.${datamart} WHERE updated_at IS NOT NULL;"
		local result
		result=$(execute_sql_query "${query}" 2>/dev/null || echo "")

		if [[ -n "${result}" ]]; then
			local freshness_seconds
			freshness_seconds=$(echo "${result}" | tr -d '[:space:]' || echo "0")
			if [[ "${freshness_seconds}" =~ ^[0-9]+$ ]]; then
				local datamart_name="${datamart#datamart_}"
				record_metric "${COMPONENT}" "datamart_freshness_seconds" "${freshness_seconds}" "component=analytics,datamart=\"${datamart_name}\""
				log_info "${COMPONENT}: Datamart ${datamart_name} freshness: ${freshness_seconds} seconds"
			fi
		fi
	done

	return 0
}

##
# Main function
##
main() {
	log_info "${COMPONENT}: Starting datamart metrics collection"

	# Load configuration
	if ! load_monitoring_config; then
		log_error "${COMPONENT}: Failed to load monitoring configuration"
		exit 1
	fi

	# Check process status for each datamart
	check_datamart_process_status "countries"
	check_datamart_process_status "users"
	check_datamart_process_status "global"

	# Collect log metrics
	collect_datamart_log_metrics

	# Check freshness from database
	check_datamart_freshness

	log_info "${COMPONENT}: Datamart metrics collection completed"
	return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
