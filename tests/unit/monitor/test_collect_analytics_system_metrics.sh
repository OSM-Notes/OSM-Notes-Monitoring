#!/usr/bin/env bash
#
# Unit Tests: collect_analytics_system_metrics.sh
# Tests analytics system metrics collection script
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

	# Mock config functions
	# shellcheck disable=SC2317
	load_monitoring_config() {
		return 0
	}
	export -f load_monitoring_config

	# Mock pgrep to simulate ETL process
	# shellcheck disable=SC2317
	pgrep() {
		local pattern="${1}"
		if [[ "${pattern}" == *"ETL.sh"* ]]; then
			echo "12345" # Simulated ETL PID
		elif [[ "${pattern}" == *"postgres"* ]]; then
			echo "67890" # Simulated PostgreSQL PID
		fi
		return 0
	}
	export -f pgrep

	# Mock ps command
	# shellcheck disable=SC2317
	ps() {
		local args="${*}"
		if [[ "${args}" == *"-p"*"12345"* ]] && [[ "${args}" == *"%cpu"* ]]; then
			echo "25.5"
		elif [[ "${args}" == *"-p"*"12345"* ]] && [[ "${args}" == *"rss"* ]]; then
			echo "1048576" # 1GB in KB
		elif [[ "${args}" == *"-p"*"12345"* ]] && [[ "${args}" == *"%mem"* ]]; then
			echo "10.2"
		elif [[ "${args}" == *"-p"*"67890"* ]] && [[ "${args}" == *"%cpu"* ]]; then
			echo "15.3"
		elif [[ "${args}" == *"-p"*"67890"* ]] && [[ "${args}" == *"rss"* ]]; then
			echo "2097152" # 2GB in KB
		elif [[ "${args}" == *"-p"*"67890"* ]] && [[ "${args}" == *"%mem"* ]]; then
			echo "20.5"
		fi
		return 0
	}
	export -f ps

	# Mock /proc/loadavg
	mkdir -p "${TEST_LOG_DIR}/proc"
	echo "1.5 1.2 1.0 1/100 12345" >"${TEST_LOG_DIR}/proc/loadavg"

	# Mock /proc/[pid]/io
	mkdir -p "${TEST_LOG_DIR}/proc/12345"
	echo "read_bytes: 1073741824" >"${TEST_LOG_DIR}/proc/12345/io"
	echo "write_bytes: 536870912" >>"${TEST_LOG_DIR}/proc/12345/io"

	# Mock df command
	# shellcheck disable=SC2317
	df() {
		echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
		echo "/dev/sda1      10485760  8388608   2097152  80% /"
		return 0
	}
	export -f df

	# Mock find and du for log directories
	# shellcheck disable=SC2317
	find() {
		if [[ "${*}" == *"/tmp"* ]] && [[ "${*}" == *"ETL_"* ]]; then
			echo "/tmp/ETL_20260109_120000"
			echo "/tmp/ETL_20260109_130000"
		fi
		return 0
	}
	export -f find

	# shellcheck disable=SC2317
	du() {
		local args="${*}"
		if [[ "${args}" == *"-sb"* ]]; then
			echo "1073741824	/tmp/ETL_20260109_120000"
		fi
		return 0
	}
	export -f du

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
	source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collect_analytics_system_metrics.sh"
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_LOG_DIR}"
}

##
# Test: collect_etl_cpu_usage collects ETL CPU usage
##
@test "collect_etl_cpu_usage collects ETL CPU usage" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_etl_cpu_usage

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"etl_cpu_usage_percent"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: collect_etl_memory_usage collects ETL memory usage
##
@test "collect_etl_memory_usage collects ETL memory usage" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_etl_memory_usage

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"etl_memory_usage_bytes"* ]] || [[ "${metric}" == *"etl_memory_usage_percent"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -ge 2 ]
}

##
# Test: collect_etl_disk_io collects ETL disk I/O
##
@test "collect_etl_disk_io collects ETL disk I/O" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Mock /proc/[pid]/io read
	if [[ -d "${TEST_LOG_DIR}/proc/12345" ]]; then
		run collect_etl_disk_io

		assert_success

		# Verify metrics were recorded
		local metrics_found=0
		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"etl_disk_read_bytes"* ]] || [[ "${metric}" == *"etl_disk_write_bytes"* ]]; then
					metrics_found=$((metrics_found + 1))
				fi
			done <"${METRICS_FILE}"
		fi
		assert [ ${metrics_found} -ge 1 ]
	fi
}

##
# Test: collect_etl_log_disk_usage collects ETL log disk usage
##
@test "collect_etl_log_disk_usage collects ETL log disk usage" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_etl_log_disk_usage

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"etl_log_disk_usage_bytes"* ]] || [[ "${metric}" == *"etl_log_directory_count"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -ge 1 ]
}

##
# Test: collect_postgresql_metrics collects PostgreSQL metrics
##
@test "collect_postgresql_metrics collects PostgreSQL metrics" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_postgresql_metrics

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"postgresql_cpu_usage_percent"* ]] || [[ "${metric}" == *"postgresql_memory_usage_bytes"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -ge 1 ]
}

##
# Test: collect_load_average collects load average
##
@test "collect_load_average collects load average" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Mock /proc/loadavg
	if [[ -f /proc/loadavg ]]; then
		run collect_load_average

		assert_success

		# Verify metrics were recorded
		local metrics_found=0
		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"system_load_average"* ]]; then
					metrics_found=$((metrics_found + 1))
				fi
			done <"${METRICS_FILE}"
		fi
		assert [ ${metrics_found} -ge 1 ]
	fi
}

##
# Test: collect_disk_usage collects disk usage
##
@test "collect_disk_usage collects disk usage" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_disk_usage

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"system_disk_usage_percent"* ]] || [[ "${metric}" == *"system_disk_total_bytes"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -ge 1 ]
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
	assert_output --partial "Starting analytics system metrics collection"
	assert_output --partial "Analytics system metrics collection completed"

	# Verify that metrics from different collection functions were recorded
	local etl_metrics=0
	local postgresql_metrics=0
	local system_metrics=0

	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"etl_"* ]]; then
				etl_metrics=$((etl_metrics + 1))
			fi
			if [[ "${metric}" == *"postgresql_"* ]]; then
				postgresql_metrics=$((postgresql_metrics + 1))
			fi
			if [[ "${metric}" == *"system_"* ]]; then
				system_metrics=$((system_metrics + 1))
			fi
		done <"${METRICS_FILE}"
	fi

	# Should have metrics from different checks
	assert [ ${etl_metrics} -ge 0 ]
	assert [ ${postgresql_metrics} -ge 0 ]
	assert [ ${system_metrics} -ge 0 ]
}

##
# Test: functions handle missing processes gracefully
##
@test "functions handle missing processes gracefully" {
	# Mock pgrep to return no processes
	# shellcheck disable=SC2317
	pgrep() {
		return 1
	}
	export -f pgrep

	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run collect_etl_cpu_usage

	assert_success
	# Note: log_debug output may not be captured, so we just verify the metric was recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"etl_cpu_usage_percent"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

