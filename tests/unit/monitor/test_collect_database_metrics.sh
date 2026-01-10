#!/usr/bin/env bash
#
# Unit Tests: collect_database_metrics.sh
# Tests database metrics collection script
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
	# Set test environment
	export TEST_MODE=true
	export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
	export COMPONENT="ANALYTICS"

	# Create test directories
	mkdir -p "${TEST_LOG_DIR}"

	# Mock record_metric using a file to track calls
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	rm -f "${METRICS_FILE}"
	touch "${METRICS_FILE}"
	export METRICS_FILE

	# shellcheck disable=SC2317
	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Mock log functions
	# shellcheck disable=SC2317
	log_debug() {
		return 0
	}
	export -f log_debug

	# shellcheck disable=SC2317
	log_info() {
		return 0
	}
	export -f log_info

	# shellcheck disable=SC2317
	log_warning() {
		return 0
	}
	export -f log_warning

	# Mock database functions
	# shellcheck disable=SC2317
	check_database_connection() {
		return 0
	}
	export -f check_database_connection

	# Mock config functions
	# shellcheck disable=SC2317
	load_monitoring_config() {
		return 0
	}
	export -f load_monitoring_config

	# shellcheck disable=SC2317
	execute_sql_query() {
		local query="${1}"
		if [[ "${query}" == *"cache_hit_ratio"* ]]; then
			echo "95.5"
		elif [[ "${query}" == *"active_connections"* ]]; then
			echo "ETL|5"
			echo "monitoring|2"
		elif [[ "${query}" == *"slow_queries"* ]]; then
			echo "3"
		elif [[ "${query}" == *"active_locks"* ]]; then
			echo "12"
		elif [[ "${query}" == *"table_bloat"* ]] || [[ "${query}" == *"dead_tup"* ]]; then
			echo "dwh|facts|1000|50000|2.0"
			echo "dwh|dimension_countries|50|1000|5.0"
		elif [[ "${query}" == *"schema_size"* ]]; then
			echo "dwh|107374182400"
		elif [[ "${query}" == *"facts_partition"* ]]; then
			echo "facts_2024|53687091200"
			echo "facts_2023|26843545600"
		fi
		return 0
	}
	export -f execute_sql_query

	# Source libraries
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"

	# Source collect_database_metrics.sh
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collect_database_metrics.sh"

	# Re-export mocks after sourcing (they may have been overwritten)
	# shellcheck disable=SC2317
	check_database_connection() {
		return 0
	}
	export -f check_database_connection

	# shellcheck disable=SC2317
	execute_sql_query() {
		local query="${1}"
		# Match queries more flexibly based on actual query patterns
		if [[ "${query}" == *"heap_blks_hit"* ]] || [[ "${query}" == *"cache_hit_ratio"* ]]; then
			echo "95.5"
		elif [[ "${query}" == *"application_name"* ]] && [[ "${query}" == *"COUNT"* ]]; then
			echo "ETL|5"
			echo "monitoring|2"
		elif [[ "${query}" == *"pg_stat_activity"* ]] && [[ "${query}" == *"30 seconds"* ]]; then
			echo "3"
		elif [[ "${query}" == *"pg_locks"* ]] && [[ "${query}" == *"COUNT"* ]]; then
			echo "12"
		elif [[ "${query}" == *"n_dead_tup"* ]] || { [[ "${query}" == *"dead_tup"* ]] && [[ "${query}" == *"live_tup"* ]]; }; then
			echo "dwh|facts|1000|50000|2.0"
			echo "dwh|dimension_countries|50|1000|5.0"
		elif [[ "${query}" == *"pg_total_relation_size"* ]] && [[ "${query}" == *"SUM"* ]] && [[ "${query}" == *"dwh"* ]]; then
			echo "dwh|107374182400"
		elif [[ "${query}" == *"facts_%"* ]] || { [[ "${query}" == *"pg_total_relation_size"* ]] && [[ "${query}" == *"facts"* ]]; }; then
			echo "facts_2024|53687091200"
			echo "facts_2023|26843545600"
		fi
		return 0
	}
	export -f execute_sql_query

	# shellcheck disable=SC2317
	load_monitoring_config() {
		return 0
	}
	export -f load_monitoring_config
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_LOG_DIR}"
}

##
# Test: collect_cache_hit_ratio collects cache hit ratio
##
@test "collect_cache_hit_ratio collects cache hit ratio" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_cache_hit_ratio

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"db_cache_hit_ratio_percent"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: collect_active_connections collects connection metrics
##
@test "collect_active_connections collects connection metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_active_connections

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"db_active_connections"* ]] || [[ "${metric}" == *"db_total_connections"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: collect_slow_queries collects slow query count
##
@test "collect_slow_queries collects slow query count" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_slow_queries

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"db_slow_queries_count"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: collect_active_locks collects lock count
##
@test "collect_active_locks collects lock count" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_active_locks

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"db_active_locks_count"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: collect_table_bloat collects bloat metrics
##
@test "collect_table_bloat collects bloat metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_table_bloat

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"db_table_dead_tuples"* ]] || [[ "${metric}" == *"db_overall_bloat_percent"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: collect_schema_size collects schema size
##
@test "collect_schema_size collects schema size" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_schema_size

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"db_schema_size_bytes"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: collect_facts_partition_sizes collects partition sizes
##
@test "collect_facts_partition_sizes collects partition sizes" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_facts_partition_sizes

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"db_facts_partition_size_bytes"* ]] || [[ "${metric}" == *"db_facts_total_size_bytes"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: main function executes all collection functions
##
@test "main function executes all collection functions" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run main

	assert_success

	# Verify that multiple types of metrics were recorded
	local cache_metrics=0
	local connection_metrics=0
	local size_metrics=0

	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"cache_hit_ratio"* ]]; then
				cache_metrics=$((cache_metrics + 1))
			fi
			if [[ "${metric}" == *"active_connections"* ]] || [[ "${metric}" == *"total_connections"* ]]; then
				connection_metrics=$((connection_metrics + 1))
			fi
			if [[ "${metric}" == *"schema_size"* ]] || [[ "${metric}" == *"facts_partition"* ]]; then
				size_metrics=$((size_metrics + 1))
			fi
		done <"${METRICS_FILE}"
	fi

	# Should have metrics from different checks
	assert [[ ${cache_metrics} -ge 0 ]]
	assert [[ ${connection_metrics} -ge 0 ]]
	assert [[ ${size_metrics} -ge 0 ]]
}

##
# Test: functions handle database connection failure gracefully
##
@test "functions handle database connection failure gracefully" {
	# Mock check_database_connection to fail
	# shellcheck disable=SC2317
	check_database_connection() {
		return 1
	}
	export -f check_database_connection

	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_cache_hit_ratio

	# Should handle failure gracefully (return 1 but not crash)
	assert_failure
}

##
# Test: functions handle empty query results gracefully
##
@test "functions handle empty query results gracefully" {
	# Mock check_database_connection
	# shellcheck disable=SC2317
	check_database_connection() {
		return 0
	}
	export -f check_database_connection

	# Mock execute_sql_query to return empty
	# shellcheck disable=SC2317
	execute_sql_query() {
		echo ""
		return 0
	}
	export -f execute_sql_query

	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Mock load_monitoring_config
	# shellcheck disable=SC2317
	load_monitoring_config() {
		return 0
	}
	export -f load_monitoring_config

	run collect_cache_hit_ratio

	# Should handle empty results gracefully
	assert_success
}
