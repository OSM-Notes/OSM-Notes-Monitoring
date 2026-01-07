# Code Coverage Explanation

## Overview

This project uses **two different methods** to measure code coverage, each serving a different purpose:

1. **Estimated Coverage** (Fast, Optimistic)
2. **Instrumented Coverage** (Slow, Accurate)

## Why Two Methods?

### Estimated Coverage (80% average)

**What it measures:**
- Presence of test files for each script
- Number of test files per script
- Heuristic calculation based on test file count

**How it works:**
- Counts test files matching each script name
- Estimates coverage: 1 test = 40%, 2 tests = 60%, 3+ tests = 80%
- Very fast (seconds)

**Use when:**
- Quick check of test coverage status
- CI/CD pipelines (fast feedback)
- Identifying scripts without tests

**Limitations:**
- Doesn't measure actual code execution
- Assumes tests cover code well
- Can be overly optimistic

### Instrumented Coverage (27% average)

**What it measures:**
- Lines of code **actually executed** during tests
- Real code coverage using `bashcov` instrumentation
- Precise measurement of executed vs total lines

**How it works:**
- Runs all tests with `bashcov` instrumentation
- Tracks which lines are executed
- Calculates: (executed lines / total lines) × 100
- Very slow (hours)

**Use when:**
- Detailed analysis of code coverage
- Identifying untested code paths
- Before releases (comprehensive check)

**Limitations:**
- Very slow (requires running all tests)
- Requires Ruby and bashcov installation
- May show low coverage for valid reasons (see below)

## Why the Gap?

The large gap between estimated (80%) and instrumented (27%) coverage is **normal and expected**:

### 1. Unit Tests vs Full Execution

**Unit tests:**
- Test individual functions in isolation
- Use `source` to load libraries
- Don't execute the full script flow
- Skip initialization code

**Example:**
```bash
# Test only tests the function
source bin/lib/metricsFunctions.sh
record_metric "component" "metric" 100

# But never executes:
# - Script initialization
# - Main function
# - Command-line argument parsing
# - Error handling in main flow
```

### 2. Extensive Mocking

**Mocks prevent real code execution:**
- `psql` is mocked → database connection code never runs
- `curl` is mocked → HTTP request code never runs
- `mutt` is mocked → email sending code never runs

**Example:**
```bash
# Mock replaces real function
psql() { echo "mocked"; }

# Real code in script:
psql -h "${dbhost}" -d "${dbname}" -c "${query}"
# This line exists but never executes because psql is mocked
```

### 3. Conditional Code Paths

**Code that only runs in production:**
- `TEST_MODE=true` skips initialization
- `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` blocks only run when script executed directly
- Production-only error handling

**Example:**
```bash
# Only runs when script executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_logging  # Never runs in tests
    main "$@"     # Never runs in tests
fi
```

### 4. Test Architecture

**Tests focus on functions, not scripts:**
- Tests call individual functions
- Don't execute `main()` functions
- Don't test command-line interfaces
- Don't test full workflows

## Which Number Should You Trust?

### Use Estimated Coverage (80%) for:
- ✅ Quick status checks
- ✅ CI/CD pipelines
- ✅ Identifying missing tests
- ✅ General project health

### Use Instrumented Coverage (27%) for:
- ✅ Detailed analysis
- ✅ Finding untested code
- ✅ Release preparation
- ✅ Understanding real coverage

## Improving Instrumented Coverage

To improve the **real** (instrumented) coverage:

### 1. Add Integration Tests

**Current:** Unit tests test functions in isolation
**Improvement:** Add tests that execute full scripts

```bash
# Example: Test full script execution
@test "monitorAPI.sh executes main function" {
    run bash bin/monitor/monitorAPI.sh check
    assert_success
}
```

### 2. Reduce Mocking Where Possible

**Current:** Everything is mocked
**Improvement:** Use real dependencies in integration tests

```bash
# Instead of mocking psql, use test database
export TEST_DB_NAME="osm_notes_monitoring_test"
# Run real psql commands against test DB
```

### 3. Test Main Functions

**Current:** Only test individual functions
**Improvement:** Test `main()` functions

```bash
# Source script and call main
source bin/monitor/monitorAPI.sh
run main "check"
assert_success
```

### 4. Test Initialization Code

**Current:** `TEST_MODE=true` skips initialization
**Improvement:** Test initialization separately

```bash
# Test initialization explicitly
export TEST_MODE=false
run init_logging "${LOG_FILE}" "component"
assert_success
```

## Generating Reports

### Estimated Coverage (Fast)
```bash
bash scripts/generate_coverage_report.sh
# Output: coverage/coverage_report.txt
```

### Instrumented Coverage (Slow)
```bash
# Run in background (takes hours)
bash scripts/run_bashcov_background.sh start

# Monitor progress
bash scripts/monitor_bashcov.sh

# Check status
bash scripts/run_bashcov_background.sh status
# Output: coverage/coverage_report_instrumented.txt
```

### Combined Report (Both Side by Side)
```bash
bash scripts/generate_coverage_combined.sh
# Output: coverage/coverage_report_combined.txt
```

## Recommendations

1. **For daily development:** Use estimated coverage (fast feedback)
2. **For releases:** Run instrumented coverage (comprehensive check)
3. **For CI/CD:** Use estimated coverage (fast enough for pipelines)
4. **For detailed analysis:** Use combined report (see both perspectives)

## Understanding the Numbers

- **Estimated 80%**: "We have tests for 80% of scripts"
- **Instrumented 27%**: "27% of code lines are executed during tests"
- **Gap 53%**: "Tests exist but don't execute much code (normal for unit tests)"

This gap is **expected** and **acceptable** for a project with extensive unit tests and mocking. The goal is to gradually improve instrumented coverage by adding integration tests and testing main functions.

## See Also

- [Code Coverage Instrumentation Guide](./CODE_COVERAGE_INSTRUMENTATION.md): How to use bashcov
- [Testing Guide](../README.md#testing): How to write tests
- Combined Coverage Report: `coverage/coverage_report_combined.txt`
