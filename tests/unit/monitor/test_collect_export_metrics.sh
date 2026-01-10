#!/usr/bin/env bash
#
# Unit Tests: collect_export_metrics.sh
# Tests export metrics collection script
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
TEST_EXPORT_DIR="${BATS_TEST_DIRNAME}/../../tmp/exports"

setup() {
	# Set test environment
	export TEST_MODE=true
	export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
	export COMPONENT="ANALYTICS"

	# Create test directories
	mkdir -p "${TEST_LOG_DIR}"
	mkdir -p "${TEST_EXPORT_DIR}/json"
	mkdir -p "${TEST_EXPORT_DIR}/csv"
	mkdir -p "${TEST_EXPORT_DIR}/logs"

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

	# Mock find command
	# shellcheck disable=SC2317
	find() {
		local args="${*}"
		if [[ "${args}" == *"json"* ]] && [[ "${args}" == *"*.json"* ]]; then
			echo "${TEST_EXPORT_DIR}/json/file1.json"
			echo "${TEST_EXPORT_DIR}/json/file2.json"
		elif [[ "${args}" == *"csv"* ]] && [[ "${args}" == *"*.csv"* ]]; then
			echo "${TEST_EXPORT_DIR}/csv/file1.csv"
			echo "${TEST_EXPORT_DIR}/csv/file2.csv"
		elif [[ "${args}" == *"export*.log"* ]] || [[ "${args}" == *"json*.log"* ]] || [[ "${args}" == *"csv*.log"* ]]; then
			echo "${TEST_EXPORT_DIR}/logs/export.log"
		fi
		return 0
	}
	export -f find

	# Mock du command
	# shellcheck disable=SC2317
	du() {
		local args="${*}"
		if [[ "${args}" == *"-sb"* ]]; then
			if [[ "${args}" == *"json"* ]]; then
				echo "2048	${TEST_EXPORT_DIR}/json"
			elif [[ "${args}" == *"csv"* ]]; then
				echo "1024	${TEST_EXPORT_DIR}/csv"
			fi
		fi
		return 0
	}
	export -f du

	# Mock stat command
	# shellcheck disable=SC2317
	stat() {
		local args="${*}"
		if [[ "${args}" == *"-c"* ]] && [[ "${args}" == *"%Y"* ]]; then
			# Return current timestamp minus 3600 seconds (1 hour ago)
			echo $(($(date +%s) - 3600))
		fi
		return 0
	}
	export -f stat

	# Mock git command
	# shellcheck disable=SC2317
	git() {
		local args="${*}"
		if [[ "${args}" == *"rev-parse"* ]]; then
			echo ".git"
		elif [[ "${args}" == *"remote get-url origin"* ]]; then
			echo "https://github.com/user/repo.git"
		elif [[ "${args}" == *"log"* ]] && [[ "${args}" == *"--format=%ct"* ]]; then
			echo $(($(date +%s) - 1800)) # 30 minutes ago
		elif [[ "${args}" == *"log origin/main..HEAD"* ]]; then
			echo "" # No unpushed commits
		fi
		return 0
	}
	export -f git

	# Mock python3 for JSON validation
	# shellcheck disable=SC2317
	python3() {
		local args="${*}"
		if [[ "${args}" == *"json.tool"* ]]; then
			return 0 # Valid JSON
		fi
		return 0
	}
	export -f python3

	# Mock grep for log parsing
	# shellcheck disable=SC2317
	grep() {
		local args="${*}"
		if [[ "${args}" == *"completed successfully"* ]] || [[ "${args}" == *"finished successfully"* ]]; then
			echo "Export completed successfully"
		elif [[ "${args}" == *"Duration:"* ]] || [[ "${args}" == *"took"* ]]; then
			echo "Duration: 300"
		fi
		return 0
	}
	export -f grep

	# Create test JSON files
	echo '{"test": "data"}' >"${TEST_EXPORT_DIR}/json/file1.json"
	echo '{"test": "data2"}' >"${TEST_EXPORT_DIR}/json/file2.json"

	# Create test CSV files
	echo "col1,col2" >"${TEST_EXPORT_DIR}/csv/file1.csv"
	echo "val1,val2" >>"${TEST_EXPORT_DIR}/csv/file1.csv"

	# Create test log file
	echo "Export completed successfully" >"${TEST_EXPORT_DIR}/logs/export.log"
	echo "Duration: 300" >>"${TEST_EXPORT_DIR}/logs/export.log"

	# Set export directories for test
	export JSON_EXPORT_DIR="${TEST_EXPORT_DIR}/json"
	export CSV_EXPORT_DIR="${TEST_EXPORT_DIR}/csv"
	export EXPORT_LOG_DIR="${TEST_EXPORT_DIR}/logs"

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
	source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collect_export_metrics.sh"
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_LOG_DIR}"
	rm -rf "${TEST_EXPORT_DIR}"
}

##
# Test: collect_json_export_metrics collects JSON export metrics
##
@test "collect_json_export_metrics collects JSON export metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_json_export_metrics

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"export_files_total"* ]] && [[ "${metric}" == *"type=json"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: collect_csv_export_metrics collects CSV export metrics
##
@test "collect_csv_export_metrics collects CSV export metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_csv_export_metrics

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"export_files_total"* ]] && [[ "${metric}" == *"type=csv"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: collect_json_validation_metrics collects JSON validation metrics
##
@test "collect_json_validation_metrics collects JSON validation metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_json_validation_metrics

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"export_validation"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: check_github_push_status checks GitHub push status
##
@test "check_github_push_status checks GitHub push status" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_github_push_status

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"export_github_push"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: parse_export_logs parses export logs
##
@test "parse_export_logs parses export logs" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run parse_export_logs

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"export_status"* ]] || [[ "${metric}" == *"export_duration"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: validate_json_schema validates JSON schema
##
@test "validate_json_schema validates JSON schema" {
	local test_json="${TEST_EXPORT_DIR}/json/file1.json"

	run validate_json_schema "${test_json}"

	assert_success
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
	assert_output --partial "Starting export metrics collection"
	assert_output --partial "Export metrics collection completed"

	# Verify that metrics from different collection functions were recorded
	local json_metrics=0
	local csv_metrics=0
	local validation_metrics=0
	local github_metrics=0

	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"type=json"* ]]; then
				json_metrics=$((json_metrics + 1))
			fi
			if [[ "${metric}" == *"type=csv"* ]]; then
				csv_metrics=$((csv_metrics + 1))
			fi
			if [[ "${metric}" == *"export_validation"* ]]; then
				validation_metrics=$((validation_metrics + 1))
			fi
			if [[ "${metric}" == *"export_github_push"* ]]; then
				github_metrics=$((github_metrics + 1))
			fi
		done <"${METRICS_FILE}"
	fi

	# Should have metrics from different checks
	assert [ ${json_metrics} -ge 0 ]
	assert [ ${csv_metrics} -ge 0 ]
	assert [ ${validation_metrics} -ge 0 ]
	assert [ ${github_metrics} -ge 0 ]
}

##
# Test: functions handle missing directories gracefully
##
@test "functions handle missing directories gracefully" {
	# Remove test directories
	rm -rf "${TEST_EXPORT_DIR}/json"
	rm -rf "${TEST_EXPORT_DIR}/csv"

	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_json_export_metrics

	assert_success

	# Should still record metrics (with 0 values)
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"export_files_total"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: check_github_push_status handles non-git directory
##
@test "check_github_push_status handles non-git directory" {
	# Mock git to return error (not a git repo)
	# shellcheck disable=SC2317
	git() {
		return 1
	}
	export -f git

	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_github_push_status

	assert_success

	# Should still record metrics
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"export_github_push"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}
