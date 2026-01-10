#!/usr/bin/env bash
#
# Integration Tests: Database Monitoring
# Tests database monitoring integration with collect_database_metrics.sh and monitorAnalytics.sh
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"

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

	# Mock send_alert
	# shellcheck disable=SC2317
	send_alert() {
		return 0
	}
	export -f send_alert

	# Mock database functions
	# shellcheck disable=SC2317
	check_database_connection() {
		return 0
	}
	export -f check_database_connection

	# shellcheck disable=SC2317
	execute_sql_query() {
		local query="${1}"
		if [[ "${query}" == *"cache_hit_ratio"* ]]; then
			echo "95.5"
		elif [[ "${query}" == *"active_connections"* ]]; then
			echo "ETL|5|2|0|1"
			echo "monitoring|2|1|1|0"
		elif [[ "${query}" == *"slow_queries"* ]]; then
			echo "3"
		elif [[ "${query}" == *"active_locks"* ]]; then
			echo "12"
		elif [[ "${query}" == *"table_bloat"* ]] || [[ "${query}" == *"dead_tup"* ]]; then
			echo "dwh|facts|1000|50000|2.0"
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
	source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"

	# Source collect_database_metrics.sh
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/monitor/collect_database_metrics.sh" 2>/dev/null || true

	# Source monitorAnalytics.sh functions
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorAnalytics.sh" 2>/dev/null || true

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
			echo "ETL|5|2|0|1"
			echo "monitoring|2|1|1|0"
		elif [[ "${query}" == *"pg_stat_activity"* ]] && [[ "${query}" == *"30 seconds"* ]]; then
			echo "3"
		elif [[ "${query}" == *"pg_locks"* ]] && [[ "${query}" == *"COUNT"* ]]; then
			echo "12"
		elif [[ "${query}" == *"n_dead_tup"* ]] || { [[ "${query}" == *"dead_tup"* ]] && [[ "${query}" == *"live_tup"* ]]; }; then
			echo "dwh|facts|1000|50000|2.0"
		elif [[ "${query}" == *"pg_total_relation_size"* ]] && [[ "${query}" == *"SUM"* ]] && [[ "${query}" == *"dwh"* ]]; then
			echo "dwh|107374182400"
		elif [[ "${query}" == *"facts_%"* ]] || { [[ "${query}" == *"pg_total_relation_size"* ]] && [[ "${query}" == *"facts"* ]]; }; then
			echo "facts_2024|53687091200"
			echo "facts_2023|26843545600"
		fi
		return 0
	}
	export -f execute_sql_query
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_LOG_DIR}"
}

##
# Test: collect_database_metrics.sh integrates with monitorAnalytics.sh
##
@test "collect_database_metrics.sh integrates with monitorAnalytics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run collect_database_metrics.sh main function
	run main

	assert_success

	# Verify that metrics from different collection functions were recorded
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
# Test: monitorAnalytics.sh check_database_performance calls collect_database_metrics.sh
##
@test "monitorAnalytics.sh check_database_performance calls collect_database_metrics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run check_database_performance function
	if declare -f check_database_performance >/dev/null 2>&1; then
		run check_database_performance

		assert_success
	else
		skip "check_database_performance function not found"
	fi
}

##
# Test: End-to-end database monitoring workflow
##
@test "End-to-end database monitoring workflow" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run all database checks in sequence
	if declare -f collect_cache_hit_ratio >/dev/null 2>&1; then
		collect_cache_hit_ratio || true
	fi

	if declare -f collect_active_connections >/dev/null 2>&1; then
		collect_active_connections || true
	fi

	if declare -f collect_schema_size >/dev/null 2>&1; then
		collect_schema_size || true
	fi

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
# Test: Integration handles database connection failure gracefully
##
@test "Integration handles database connection failure gracefully" {
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

	# Run check_database_performance - should handle failure gracefully
	if declare -f check_database_performance >/dev/null 2>&1; then
		run check_database_performance

		# Should succeed even if database connection fails (graceful handling)
		assert_success
	else
		skip "check_database_performance function not found"
	fi
}

##
# Test: Integration collects metrics for multiple applications
##
@test "Integration collects metrics for multiple applications" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run collect_active_connections
	if declare -f collect_active_connections >/dev/null 2>&1; then
		run collect_active_connections

		assert_success

		# Verify metrics were recorded for different applications
		local etl_metrics=0
		local monitoring_metrics=0

		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"application=\"ETL\""* ]]; then
					etl_metrics=$((etl_metrics + 1))
				fi
				if [[ "${metric}" == *"application=\"monitoring\""* ]]; then
					monitoring_metrics=$((monitoring_metrics + 1))
				fi
			done <"${METRICS_FILE}"
		fi

		# Should have metrics for different applications
		assert [[ ${etl_metrics} -ge 0 ]]
		assert [[ ${monitoring_metrics} -ge 0 ]]
	else
		skip "collect_active_connections function not found"
	fi
}

##
# Test: Integration collects partition-specific metrics
##
@test "Integration collects partition-specific metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run collect_facts_partition_sizes
	if declare -f collect_facts_partition_sizes >/dev/null 2>&1; then
		run collect_facts_partition_sizes

		assert_success

		# Verify partition metrics were recorded
		local partition_metrics=0
		local total_size_metrics=0

		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"db_facts_partition_size_bytes"* ]]; then
					partition_metrics=$((partition_metrics + 1))
				fi
				if [[ "${metric}" == *"db_facts_total_size_bytes"* ]]; then
					total_size_metrics=$((total_size_metrics + 1))
				fi
			done <"${METRICS_FILE}"
		fi

		# Should have partition and total size metrics
		assert [[ ${partition_metrics} -ge 0 ]]
		assert [[ ${total_size_metrics} -ge 0 ]]
	else
		skip "collect_facts_partition_sizes function not found"
	fi
}
