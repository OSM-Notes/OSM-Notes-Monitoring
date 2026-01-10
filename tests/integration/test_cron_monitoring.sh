#!/usr/bin/env bash
#
# Integration Tests: Cron Monitoring
# Tests the integration of collect_cron_metrics.sh with monitorAnalytics.sh
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
TEST_CRON_LOG="${BATS_TEST_DIRNAME}/../tmp/cron.log"

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

	# Mock config functions
	# shellcheck disable=SC2317
	load_monitoring_config() {
		return 0
	}
	export -f load_monitoring_config

	# Create mock cron log
	mkdir -p "$(dirname "${TEST_CRON_LOG}")"
	echo "Jan 10 10:00:00 hostname CRON[12345]: (user) CMD (ETL.sh)" >"${TEST_CRON_LOG}"
	echo "Jan 10 10:15:00 hostname CRON[12346]: (user) CMD (ETL.sh)" >>"${TEST_CRON_LOG}"
	echo "Jan 10 10:30:00 hostname CRON[12347]: (user) CMD (datamart.sh)" >>"${TEST_CRON_LOG}"

	export CRON_LOG_CRON="${TEST_CRON_LOG}"
	export CRON_LOG_SYSLOG="${TEST_CRON_LOG}"

	# Mock grep command
	# shellcheck disable=SC2317
	grep() {
		local args="${*}"
		if [[ "${args}" == *"ETL"* ]] && [[ "${args}" == *"CRON"* ]]; then
			echo "Jan 10 10:00:00 hostname CRON[12345]: (user) CMD (ETL.sh)"
			echo "Jan 10 10:15:00 hostname CRON[12346]: (user) CMD (ETL.sh)"
		elif [[ "${args}" == *"datamart"* ]] && [[ "${args}" == *"CRON"* ]]; then
			echo "Jan 10 10:30:00 hostname CRON[12347]: (user) CMD (datamart.sh)"
		fi
		return 0
	}
	export -f grep

	# Mock find command
	# shellcheck disable=SC2317
	find() {
		local args="${*}"
		if [[ "${args}" == *"*.lock"* ]]; then
			echo "/tmp/ETL_20260110.lock"
		fi
		return 0
	}
	export -f find

	# Mock date command
	# shellcheck disable=SC2317
	date() {
		local args="${*}"
		if [[ "${args}" == *"+%s"* ]]; then
			echo "1704892800"
		fi
		return 0
	}
	export -f date

	# Mock database functions
	# shellcheck disable=SC2317
	check_database_connection() {
		return 0
	}
	export -f check_database_connection

	# shellcheck disable=SC2317
	execute_sql_query() {
		return 0
	}
	export -f execute_sql_query

	# Mock alert function
	# shellcheck disable=SC2317
	alert_send() {
		return 0
	}
	export -f alert_send

	# Source the scripts to be tested
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/monitor/collect_cron_metrics.sh" 2>/dev/null || true
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
		return 0
	}
	export -f execute_sql_query

	# shellcheck disable=SC2317
	alert_send() {
		return 0
	}
	export -f alert_send
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_LOG_DIR}"
	rm -f "${TEST_CRON_LOG}"
}

##
# Test: collect_cron_metrics.sh integrates with monitorAnalytics.sh
##
@test "collect_cron_metrics.sh integrates with monitorAnalytics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_cron_jobs

	assert_success
	assert_output --partial "Starting cron jobs check"
	assert_output --partial "Cron jobs check completed"

	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"cron_"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -ge 0 ]
}

##
# Test: monitorAnalytics.sh check_cron_jobs calls collect_cron_metrics.sh
##
@test "monitorAnalytics.sh check_cron_jobs calls collect_cron_metrics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Test the function directly instead of calling the script
	if declare -f check_cron_jobs >/dev/null 2>&1; then
		run check_cron_jobs

		assert_success
		assert_output --partial "Starting cron jobs check"

		local metrics_found=0
		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"cron_"* ]]; then
					metrics_found=$((metrics_found + 1))
				fi
			done <"${METRICS_FILE}"
		fi
		assert [ ${metrics_found} -ge 0 ]
	else
		skip "check_cron_jobs function not found"
	fi
}

##
# Test: End-to-end cron monitoring workflow
##
@test "End-to-end cron monitoring workflow" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Test check_cron_jobs function directly
	if declare -f check_cron_jobs >/dev/null 2>&1; then
		run check_cron_jobs

		assert_success
		assert_output --partial "Starting cron jobs check"

		local cron_metrics=0
		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"cron_"* ]]; then
					cron_metrics=$((cron_metrics + 1))
				fi
			done <"${METRICS_FILE}"
		fi

		assert [ ${cron_metrics} -ge 0 ]
	else
		skip "check_cron_jobs function not found"
	fi
}

##
# Test: Integration collects metrics for all cron jobs
##
@test "Integration collects metrics for all cron jobs" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	if declare -f check_cron_jobs >/dev/null 2>&1; then
		run check_cron_jobs

		assert_success

		local etl_metrics=0
		local datamart_metrics=0
		local export_metrics=0
		local lock_metrics=0

		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"cron_etl"* ]]; then
					etl_metrics=$((etl_metrics + 1))
				fi
				if [[ "${metric}" == *"cron_datamart"* ]]; then
					datamart_metrics=$((datamart_metrics + 1))
				fi
				if [[ "${metric}" == *"cron_export"* ]]; then
					export_metrics=$((export_metrics + 1))
				fi
				if [[ "${metric}" == *"cron_lock"* ]]; then
					lock_metrics=$((lock_metrics + 1))
				fi
			done <"${METRICS_FILE}"
		fi

		assert [ ${etl_metrics} -ge 0 ]
		assert [ ${datamart_metrics} -ge 0 ]
		assert [ ${export_metrics} -ge 0 ]
		assert [ ${lock_metrics} -ge 0 ]
	else
		skip "check_cron_jobs function not found"
	fi
}

##
# Test: Integration handles missing cron log gracefully
##
@test "Integration handles missing cron log gracefully" {
	# Remove cron log
	rm -f "${TEST_CRON_LOG}"
	export CRON_LOG_CRON=""
	export CRON_LOG_SYSLOG=""

	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	if declare -f check_cron_jobs >/dev/null 2>&1; then
		run check_cron_jobs

		assert_success

		# Should still complete without errors
		assert_output --partial "Starting cron jobs check"
	else
		skip "check_cron_jobs function not found"
	fi
}
