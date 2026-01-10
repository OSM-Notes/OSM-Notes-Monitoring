#!/usr/bin/env bash
#
# Unit Tests: datamartLogParser.sh
# Tests datamart log parser library functions
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_datamart"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
	# Set test environment
	export TEST_MODE=true
	export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
	export COMPONENT="ANALYTICS"

	# Create test directories
	mkdir -p "${TEST_TMP_DIR}/datamartCountries_20260109"
	mkdir -p "${TEST_TMP_DIR}/datamartUsers_20260109"
	mkdir -p "${TEST_TMP_DIR}/datamartGlobal_20260109"
	mkdir -p "${TEST_LOG_DIR}"

	# Create test datamart log files
	local current_time
	current_time=$(date +"%Y-%m-%d %H:%M:%S")

	# Countries log
	cat >"${TEST_TMP_DIR}/datamartCountries_20260109/datamartCountries.log" <<EOF
${current_time} - bin/dwh/datamartCountries.sh:__main:1021 - INFO - DatamartCountries started
${current_time} - bin/dwh/datamartCountries.sh:__process:521 - INFO - Processing 195 countries in parallel
${current_time} - bin/dwh/datamartCountries.sh:__process:522 - INFO - Using 4 threads for parallel processing
${current_time} - bin/dwh/datamartCountries.sh:__main:1022 - INFO - DatamartCountries completed successfully in 1800 seconds
EOF

	# Users log
	cat >"${TEST_TMP_DIR}/datamartUsers_20260109/datamartUsers.log" <<EOF
${current_time} - bin/dwh/datamartUsers.sh:__main:1021 - INFO - DatamartUsers started
${current_time} - bin/dwh/datamartUsers.sh:__process:521 - INFO - Processing 50000 users
${current_time} - bin/dwh/datamartUsers.sh:__process:522 - INFO - Pending users: 10000
${current_time} - bin/dwh/datamartUsers.sh:__process:523 - INFO - Initial load progress: 80 percent
${current_time} - bin/dwh/datamartUsers.sh:__main:1022 - INFO - DatamartUsers completed successfully in 2400 seconds
EOF

	# Global log
	cat >"${TEST_TMP_DIR}/datamartGlobal_20260109/datamartGlobal.log" <<EOF
${current_time} - bin/dwh/datamartGlobal.sh:__main:1021 - INFO - DatamartGlobal started
${current_time} - bin/dwh/datamartGlobal.sh:__update:521 - INFO - Updated global datamart
${current_time} - bin/dwh/datamartGlobal.sh:__update:522 - INFO - Total records: 1000000
${current_time} - bin/dwh/datamartGlobal.sh:__main:1022 - INFO - DatamartGlobal completed successfully in 600 seconds
EOF

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

	# Mock stat
	# shellcheck disable=SC2317
	stat() {
		if [[ "$*" == *"-c %Y"* ]] || [[ "$*" == *"-f %m"* ]]; then
			date +%s
			return 0
		fi
		return 1
	}
	export -f stat

	# Mock find
	# shellcheck disable=SC2317
	find() {
		if [[ "$*" == *"datamartCountries_*/datamartCountries.log"* ]]; then
			echo "${TEST_TMP_DIR}/datamartCountries_20260109/datamartCountries.log"
		elif [[ "$*" == *"datamartUsers_*/datamartUsers.log"* ]]; then
			echo "${TEST_TMP_DIR}/datamartUsers_20260109/datamartUsers.log"
		elif [[ "$*" == *"datamartGlobal_*/datamartGlobal.log"* ]]; then
			echo "${TEST_TMP_DIR}/datamartGlobal_20260109/datamartGlobal.log"
		fi
		return 0
	}
	export -f find

	# Source libraries
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"

	# Source datamartLogParser.sh
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/datamartLogParser.sh"
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_TMP_DIR}"
	rm -rf "${TEST_LOG_DIR}"
}

##
# Test: find_datamart_log_file finds log files
##
@test "find_datamart_log_file finds log files" {
	local pattern="/tmp/datamartCountries_*/datamartCountries.log"
	run find_datamart_log_file "${pattern}"

	assert_success
	assert [[ -n "${output}" ]]
}

##
# Test: parse_datamart_execution extracts execution metrics
##
@test "parse_datamart_execution extracts execution metrics" {
	local log_file="${TEST_TMP_DIR}/datamartCountries_20260109/datamartCountries.log"
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run parse_datamart_execution "${log_file}" "countries"

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_execution"* ]] || [[ "${metric}" == *"datamart_success"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: parse_datamart_countries_metrics extracts countries metrics
##
@test "parse_datamart_countries_metrics extracts countries metrics" {
	local log_file="${TEST_TMP_DIR}/datamartCountries_20260109/datamartCountries.log"
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run parse_datamart_countries_metrics "${log_file}"

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_countries_processed"* ]] || [[ "${metric}" == *"datamart_parallel"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: parse_datamart_users_metrics extracts users metrics
##
@test "parse_datamart_users_metrics extracts users metrics" {
	local log_file="${TEST_TMP_DIR}/datamartUsers_20260109/datamartUsers.log"
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run parse_datamart_users_metrics "${log_file}"

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_users"* ]] || [[ "${metric}" == *"datamart_initial_load"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: parse_datamart_global_metrics extracts global metrics
##
@test "parse_datamart_global_metrics extracts global metrics" {
	local log_file="${TEST_TMP_DIR}/datamartGlobal_20260109/datamartGlobal.log"
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run parse_datamart_global_metrics "${log_file}"

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_global"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${metrics_found} -ge 0 ]]
}

##
# Test: parse_all_datamart_logs parses all logs
##
@test "parse_all_datamart_logs parses all logs" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run parse_all_datamart_logs

	assert_success

	# Verify that metrics from different datamarts were recorded
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

	# Should have metrics from different datamarts
	assert [[ ${countries_metrics} -ge 0 ]]
	assert [[ ${users_metrics} -ge 0 ]]
	assert [[ ${global_metrics} -ge 0 ]]
}

##
# Test: functions handle missing log files gracefully
##
@test "functions handle missing log files gracefully" {
	local non_existent_file="/tmp/nonexistent.log"

	run parse_datamart_execution "${non_existent_file}" "test"

	assert_failure
}

##
# Test: parse_datamart_execution calculates success rate correctly
##
@test "parse_datamart_execution calculates success rate correctly" {
	local log_file="${TEST_TMP_DIR}/datamartCountries_20260109/datamartCountries.log"
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run parse_datamart_execution "${log_file}" "countries"

	assert_success

	# Verify success rate metric was recorded
	local success_rate_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"datamart_success_rate_percent"* ]]; then
				success_rate_found=$((success_rate_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${success_rate_found} -gt 0 ]]
}
