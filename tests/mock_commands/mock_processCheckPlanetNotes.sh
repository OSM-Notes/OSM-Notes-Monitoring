#!/usr/bin/env bash
#
# Mock processCheckPlanetNotes.sh
# Simulates the Planet notes check processing script for end-to-end testing
#
# Version: 1.0.0
# Date: 2025-12-26
#

set -euo pipefail

# Mock configuration
MOCK_LOG_DIR="${MOCK_LOG_DIR:-/tmp/mock_ingestion_logs}"
MOCK_DATA_DIR="${MOCK_DATA_DIR:-/tmp/mock_ingestion_data}"
MOCK_CHECK_DURATION="${MOCK_CHECK_DURATION:-300}"

# Create directories if they don't exist
mkdir -p "${MOCK_LOG_DIR}"
mkdir -p "${MOCK_DATA_DIR}"

# Log file
LOG_FILE="${MOCK_LOG_DIR}/processCheckPlanetNotes.log"

# Function to log messages
log_message() {
    local level="${1}"
    shift
    local message="${*}"
    echo "$(date -u +"%Y-%m-%d %H:%M:%S") ${level}: ${message}" >> "${LOG_FILE}"
}

# Simulate script execution
log_message "INFO" "Starting Planet notes check processing"

# Simulate processing time (use configured duration or default)
sleep "${MOCK_CHECK_DURATION}"

log_message "INFO" "Planet notes check processing completed successfully"
exit 0


