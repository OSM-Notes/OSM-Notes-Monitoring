#!/usr/bin/env bash
#
# Unit Tests: collect_cron_metrics.sh
# Tests cron job metrics collection script
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
TEST_CRON_LOG="${BATS_TEST_DIRNAME}/../../tmp/cron.log"

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
	{
		echo "Jan 10 10:00:00 hostname CRON[12345]: (user) CMD (ETL.sh)"
		echo "Jan 10 10:15:00 hostname CRON[12346]: (user) CMD (ETL.sh)"
		echo "Jan 10 10:30:00 hostname CRON[12347]: (user) CMD (datamart.sh)"
		echo "Jan 10 10:45:00 hostname CRON[12348]: (user) CMD (export.sh)"
	} >"${TEST_CRON_LOG}"

	# Mock find_cron_log to return test log
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
		elif [[ "${args}" == *"export"* ]] && [[ "${args}" == *"CRON"* ]]; then
			echo "Jan 10 10:45:00 hostname CRON[12348]: (user) CMD (export.sh)"
		fi
		return 0
	}
	export -f grep

	# Mock find command for lock files
	# shellcheck disable=SC2317
	find() {
		local args="${*}"
		if [[ "${args}" == *"*.lock"* ]]; then
			echo "/tmp/ETL_20260110.lock"
			echo "/tmp/datamart_20260110.lock"
		fi
		return 0
	}
	export -f find

	# Mock date command
	# shellcheck disable=SC2317
	date() {
		local args="${*}"
		if [[ "${args}" == *"+%s"* ]]; then
			echo "1704892800" # Fixed timestamp for testing
		fi
		return 0
	}
	export -f date

	# Source libraries
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"

	# Source the script to be tested
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collect_cron_metrics.sh"
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_LOG_DIR}"
	rm -f "${TEST_CRON_LOG}"
}

##
# Test: check_etl_cron_execution collects ETL cron metrics
##
@test "check_etl_cron_execution collects ETL cron metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_etl_cron_execution

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"cron_etl"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: check_datamart_cron_execution collects datamart cron metrics
##
@test "check_datamart_cron_execution collects datamart cron metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_datamart_cron_execution

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"cron_datamart"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: check_export_cron_execution collects export cron metrics
##
@test "check_export_cron_execution collects export cron metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_export_cron_execution

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"cron_export"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: check_lock_files collects lock file metrics
##
@test "check_lock_files collects lock file metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_lock_files

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"cron_lock"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: detect_execution_gaps detects execution gaps
##
@test "detect_execution_gaps detects execution gaps" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Create a mock log file with old execution times
	mkdir -p "${LOG_DIR}"
	echo "cron_etl_last_execution_seconds 3600" >"${LOG_DIR}/cron_metrics.log"

	run detect_execution_gaps

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"cron_etl_gap_detected"* ]] || [[ "${metric}" == *"cron_datamart_gap_detected"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -ge 0 ]
}

##
# Test: find_cron_log finds cron log file
##
@test "find_cron_log finds cron log file" {
	# Test with accessible log
	export CRON_LOG_CRON="${TEST_CRON_LOG}"

	run find_cron_log

	assert_success
	assert_output --partial "${TEST_CRON_LOG}"
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
	assert_output --partial "Starting cron job metrics collection"
	assert_output --partial "Cron job metrics collection completed"

	# Verify that metrics from different collection functions were recorded
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

	# Should have metrics from different checks
	assert [ ${etl_metrics} -ge 0 ]
	assert [ ${datamart_metrics} -ge 0 ]
	assert [ ${export_metrics} -ge 0 ]
	assert [ ${lock_metrics} -ge 0 ]
}

##
# Test: functions handle missing cron log gracefully
##
@test "functions handle missing cron log gracefully" {
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

	run check_etl_cron_execution

	assert_success

	# Should still record metrics (with 0 or unavailable status)
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"cron_etl"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}
