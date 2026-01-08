#!/usr/bin/env bash
#
# Helper function to run scripts in a way that bashcov can track
# When running under bashcov, executes scripts directly (without bash)
# so bashcov can track coverage. Otherwise, executes normally with bash.
#
# Usage:
#   run_script_for_coverage "bin/monitor/monitorData.sh" "backup_freshness"
#
# Version: 1.0.0
# Date: 2026-01-08
#

##
# Detect if we're running under bashcov
##
is_running_under_bashcov() {
    # Check if bashcov is in the process tree
    local ppid=$$
    local max_depth=5
    local depth=0
    
    while [[ ${depth} -lt ${max_depth} ]] && [[ ${ppid} -gt 1 ]]; do
        local cmdline
        cmdline=$(tr '\0' ' ' < "/proc/${ppid}/cmdline" 2>/dev/null || echo "")
        if echo "${cmdline}" | grep -q "bashcov"; then
            return 0
        fi
        ppid=$(ps -o ppid= -p "${ppid}" 2>/dev/null | tr -d ' ' || echo "")
        if [[ -z "${ppid}" ]] || [[ "${ppid}" == "1" ]]; then
            break
        fi
        depth=$((depth + 1))
    done
    
    # Also check environment variables that bashcov might set
    if [[ -n "${BASHCOV_ROOT:-}" ]] || [[ -n "${COVERAGE_DIR:-}" ]]; then
        return 0
    fi
    
    return 1
}

##
# Run a script in a way that bashcov can track
##
run_script_for_coverage() {
    local script_path="${1}"
    shift
    local args=("$@")
    
    # Make script executable
    if [[ -f "${script_path}" ]]; then
        chmod +x "${script_path}" 2>/dev/null || true
    fi
    
    # If running under bashcov, execute script directly (bashcov will track it)
    # Otherwise, execute with bash (normal behavior)
    if is_running_under_bashcov; then
        # Execute directly - bashcov will track it
        "${script_path}" "${args[@]}"
    else
        # Execute with bash (normal behavior for tests)
        bash "${script_path}" "${args[@]}"
    fi
}

# Export function so it can be used in tests
export -f run_script_for_coverage
export -f is_running_under_bashcov
