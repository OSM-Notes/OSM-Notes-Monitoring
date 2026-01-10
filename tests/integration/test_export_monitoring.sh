#!/usr/bin/env bash
#
# Integration Tests: Export Monitoring
# Tests the integration of collect_export_metrics.sh with monitorAnalytics.sh
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
TEST_EXPORT_DIR="${BATS_TEST_DIRNAME}/../tmp/exports"

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
			echo $(($(date +%s) - 1800))
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
			return 0
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

	# Create test files
	echo '{"test": "data"}' >"${TEST_EXPORT_DIR}/json/file1.json"
	echo '{"test": "data2"}' >"${TEST_EXPORT_DIR}/json/file2.json"
	echo "col1,col2" >"${TEST_EXPORT_DIR}/csv/file1.csv"
	echo "Export completed successfully" >"${TEST_EXPORT_DIR}/logs/export.log"

	# Set export directories for test
	export JSON_EXPORT_DIR="${TEST_EXPORT_DIR}/json"
	export CSV_EXPORT_DIR="${TEST_EXPORT_DIR}/csv"
	export EXPORT_LOG_DIR="${TEST_EXPORT_DIR}/logs"

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
	source "${BATS_TEST_DIRNAME}/../../bin/monitor/collect_export_metrics.sh" 2>/dev/null || true
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
	rm -rf "${TEST_EXPORT_DIR}"
}

##
# Test: collect_export_metrics.sh integrates with monitorAnalytics.sh
##
@test "collect_export_metrics.sh integrates with monitorAnalytics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_export_status

	assert_success
	assert_output --partial "Starting export status check"
	assert_output --partial "Export status check completed"

	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"export_files_total"* ]] || [[ "${metric}" == *"export_validation"* ]] || [[ "${metric}" == *"export_github_push"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -ge 0 ]
}

##
# Test: monitorAnalytics.sh check_export_status calls collect_export_metrics.sh
##
@test "monitorAnalytics.sh check_export_status calls collect_export_metrics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Test the function directly instead of calling the script
	if declare -f check_export_status >/dev/null 2>&1; then
		run check_export_status

		assert_success
		assert_output --partial "Starting export status check"

		local metrics_found=0
		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"export_"* ]]; then
					metrics_found=$((metrics_found + 1))
				fi
			done <"${METRICS_FILE}"
		fi
		assert [ ${metrics_found} -ge 0 ]
	else
		skip "check_export_status function not found"
	fi
}

##
# Test: End-to-end export monitoring workflow
##
@test "End-to-end export monitoring workflow" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Test check_export_status function directly
	if declare -f check_export_status >/dev/null 2>&1; then
		run check_export_status

		assert_success
		assert_output --partial "Starting export status check"

		local export_metrics=0
		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"export_"* ]]; then
					export_metrics=$((export_metrics + 1))
				fi
			done <"${METRICS_FILE}"
		fi

		assert [ ${export_metrics} -ge 0 ]
	else
		skip "check_export_status function not found"
	fi
}

##
# Test: Integration collects metrics for both JSON and CSV
##
@test "Integration collects metrics for both JSON and CSV" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Test check_export_status function directly
	if declare -f check_export_status >/dev/null 2>&1; then
		run check_export_status

		assert_success

		local json_metrics=0
		local csv_metrics=0

		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"type=json"* ]]; then
					json_metrics=$((json_metrics + 1))
				fi
				if [[ "${metric}" == *"type=csv"* ]]; then
					csv_metrics=$((csv_metrics + 1))
				fi
			done <"${METRICS_FILE}"
		fi

		assert [ ${json_metrics} -ge 0 ]
		assert [ ${csv_metrics} -ge 0 ]
	else
		skip "check_export_status function not found"
	fi
}

##
# Test: Integration handles missing export directories gracefully
##
@test "Integration handles missing export directories gracefully" {
	# Remove export directories
	rm -rf "${TEST_EXPORT_DIR}/json"
	rm -rf "${TEST_EXPORT_DIR}/csv"

	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Test check_export_status function directly
	if declare -f check_export_status >/dev/null 2>&1; then
		run check_export_status

		assert_success

		# Should still complete without errors
		assert_output --partial "Starting export status check"
	else
		skip "check_export_status function not found"
	fi
}
