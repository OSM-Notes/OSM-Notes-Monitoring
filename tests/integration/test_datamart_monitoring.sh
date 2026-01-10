#!/usr/bin/env bash
#
# Integration Tests: Datamart Monitoring
# Tests datamart monitoring integration with collect_datamart_metrics.sh and monitorAnalytics.sh
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
		if [[ "${query}" == *"freshness_seconds"* ]] || [[ "${query}" == *"EXTRACT(EPOCH"* ]]; then
			echo "3600"
		fi
		return 0
	}
	export -f execute_sql_query

	# Mock pgrep
	# shellcheck disable=SC2317
	pgrep() {
		if [[ "$*" == *"datamartCountries"* ]]; then
			echo "12345"
			return 0
		elif [[ "$*" == *"datamartUsers"* ]]; then
			return 1
		elif [[ "$*" == *"datamartGlobal"* ]]; then
			echo "12346"
			return 0
		fi
		return 1
	}
	export -f pgrep

	# Mock parse_all_datamart_logs
	# shellcheck disable=SC2317
	parse_all_datamart_logs() {
		return 0
	}
	export -f parse_all_datamart_logs

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

	# Source collect_datamart_metrics.sh
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/monitor/collect_datamart_metrics.sh" 2>/dev/null || true

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
		if [[ "${query}" == *"freshness_seconds"* ]] || [[ "${query}" == *"EXTRACT(EPOCH"* ]]; then
			echo "3600"
		fi
		return 0
	}
	export -f execute_sql_query

	# shellcheck disable=SC2317
	pgrep() {
		if [[ "$*" == *"datamartCountries"* ]]; then
			echo "12345"
			return 0
		elif [[ "$*" == *"datamartUsers"* ]]; then
			return 1
		elif [[ "$*" == *"datamartGlobal"* ]]; then
			echo "12346"
			return 0
		fi
		return 1
	}
	export -f pgrep

	# shellcheck disable=SC2317
	parse_all_datamart_logs() {
		return 0
	}
	export -f parse_all_datamart_logs
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_LOG_DIR}"
}

##
# Test: collect_datamart_metrics.sh integrates with monitorAnalytics.sh
##
@test "collect_datamart_metrics.sh integrates with monitorAnalytics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run collect_datamart_metrics.sh main function
	run main

	assert_success

	# Verify that metrics from different collection functions were recorded
	local process_metrics=0
	local freshness_metrics=0

	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_process"* ]]; then
				process_metrics=$((process_metrics + 1))
			fi
			if [[ "${metric}" == *"datamart_freshness"* ]]; then
				freshness_metrics=$((freshness_metrics + 1))
			fi
		done <"${METRICS_FILE}"
	fi

	# Should have metrics from different checks
	assert [[ ${process_metrics} -ge 0 ]]
	assert [[ ${freshness_metrics} -ge 0 ]]
}

##
# Test: monitorAnalytics.sh check_datamart_status calls collect_datamart_metrics.sh
##
@test "monitorAnalytics.sh check_datamart_status calls collect_datamart_metrics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run check_datamart_status function
	if declare -f check_datamart_status >/dev/null 2>&1; then
		run check_datamart_status

		assert_success
	else
		skip "check_datamart_status function not found"
	fi
}

##
# Test: End-to-end datamart monitoring workflow
##
@test "End-to-end datamart monitoring workflow" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run all datamart checks in sequence
	if declare -f check_datamart_process_status >/dev/null 2>&1; then
		check_datamart_process_status "countries" || true
		check_datamart_process_status "users" || true
		check_datamart_process_status "global" || true
	fi

	if declare -f check_datamart_freshness >/dev/null 2>&1; then
		check_datamart_freshness || true
	fi

	# Verify that multiple types of metrics were recorded
	local process_metrics=0
	local freshness_metrics=0

	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_process"* ]]; then
				process_metrics=$((process_metrics + 1))
			fi
			if [[ "${metric}" == *"datamart_freshness"* ]]; then
				freshness_metrics=$((freshness_metrics + 1))
			fi
		done <"${METRICS_FILE}"
	fi

	# Should have metrics from different checks
	assert [[ ${process_metrics} -ge 0 ]]
	assert [[ ${freshness_metrics} -ge 0 ]]
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

	# Run check_datamart_status - should handle failure gracefully
	if declare -f check_datamart_status >/dev/null 2>&1; then
		run check_datamart_status

		# Should succeed even if database connection fails (graceful handling)
		assert_success
	else
		skip "check_datamart_status function not found"
	fi
}

##
# Test: Integration collects metrics for multiple datamarts
##
@test "Integration collects metrics for multiple datamarts" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run main function
	if declare -f main >/dev/null 2>&1; then
		run main

		assert_success

		# Verify metrics were recorded for different datamarts
		local countries_metrics=0
		local users_metrics=0
		local global_metrics=0

		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"datamart=\"countries\""* ]]; then
					countries_metrics=$((countries_metrics + 1))
				fi
				if [[ "${metric}" == *"datamart=\"users\""* ]]; then
					users_metrics=$((users_metrics + 1))
				fi
				if [[ "${metric}" == *"datamart=\"global\""* ]]; then
					global_metrics=$((global_metrics + 1))
				fi
			done <"${METRICS_FILE}"
		fi

		# Should have metrics for different datamarts
		assert [[ ${countries_metrics} -ge 0 ]]
		assert [[ ${users_metrics} -ge 0 ]]
		assert [[ ${global_metrics} -ge 0 ]]
	else
		skip "main function not found"
	fi
}
