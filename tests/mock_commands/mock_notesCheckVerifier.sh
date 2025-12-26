#!/usr/bin/env bash
#
# Mock notesCheckVerifier.sh
# Simulates the notes check verifier script for end-to-end testing
#
# Version: 1.0.0
# Date: 2025-12-26
#

set -euo pipefail

# Mock configuration
MOCK_LOG_DIR="${MOCK_LOG_DIR:-/tmp/mock_ingestion_logs}"
MOCK_DATA_DIR="${MOCK_DATA_DIR:-/tmp/mock_ingestion_data}"
MOCK_VERIFICATION_PASSES="${MOCK_VERIFICATION_PASSES:-true}"
MOCK_DISCREPANCIES="${MOCK_DISCREPANCIES:-0}"

# Create directories if they don't exist
mkdir -p "${MOCK_LOG_DIR}"
mkdir -p "${MOCK_DATA_DIR}"

# Log file
LOG_FILE="${MOCK_LOG_DIR}/notesCheckVerifier.log"

# Function to log messages
log_message() {
    local level="${1}"
    shift
    local message="${*}"
    echo "$(date -u +"%Y-%m-%d %H:%M:%S") ${level}: ${message}" >> "${LOG_FILE}"
}

# Simulate script execution
log_message "INFO" "Starting notes verification"

# Simulate processing time
sleep "${MOCK_PROCESSING_TIME:-3}"

# Simulate verification results
if [[ "${MOCK_VERIFICATION_PASSES}" == "true" ]]; then
    log_message "INFO" "Verification passed: All notes match"
else
    log_message "ERROR" "Verification failed: ${MOCK_DISCREPANCIES} discrepancies found"
    exit 1
fi

# Simulate discrepancies if configured
if [[ "${MOCK_DISCREPANCIES}" -gt 0 ]]; then
    for ((i=1; i<=MOCK_DISCREPANCIES; i++)); do
        log_message "WARNING" "Discrepancy ${i}: Note ID ${i} mismatch between Planet and API"
    done
fi

log_message "INFO" "Notes verification completed"
exit 0


