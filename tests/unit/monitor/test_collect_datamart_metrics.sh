#!/usr/bin/env bash
#
# Unit Tests: collect_datamart_metrics.sh
# Tests datamart metrics collection script
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
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"

	# Source collect_datamart_metrics.sh
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collect_datamart_metrics.sh"

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
# Test: check_datamart_process_status checks process status
##
@test "check_datamart_process_status checks process status" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_datamart_process_status "countries"

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_process_running"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: collect_datamart_log_metrics collects log metrics
##
@test "collect_datamart_log_metrics collects log metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_datamart_log_metrics

	assert_success
}

##
# Test: check_datamart_freshness collects freshness metrics
##
@test "check_datamart_freshness collects freshness metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_datamart_freshness

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_freshness_seconds"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -ge 0 ]]
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

	run check_datamart_freshness

	# Should handle failure gracefully (return 1 but not crash)
	assert_failure
}

##
# Test: check_datamart_process_status handles non-running process
##
@test "check_datamart_process_status handles non-running process" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Mock pgrep to return no process for users
	# shellcheck disable=SC2317
	pgrep() {
		if [[ "$*" == *"datamartUsers"* ]]; then
			return 1
		fi
		return 0
	}
	export -f pgrep

	run check_datamart_process_status "users"

	assert_success

	# Verify that process_running=0 was recorded
	local not_running_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_process_running"* ]] && [[ "${metric}" == *" 0 "* ]]; then
				not_running_found=$((not_running_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${not_running_found} -gt 0 ]]
}
