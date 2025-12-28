-- Data Integrity Queries
-- Queries for monitoring file integrity and data validation

-- Get file integrity statistics
-- Returns: files_checked, integrity_failures, integrity_success_rate_percent
SELECT 
    SUM(CASE WHEN metric_name = 'files_checked' THEN metric_value::numeric ELSE 0 END) as files_checked,
    SUM(CASE WHEN metric_name = 'integrity_failures' THEN metric_value::numeric ELSE 0 END) as integrity_failures,
    CASE 
        WHEN SUM(CASE WHEN metric_name = 'files_checked' THEN metric_value::numeric ELSE 0 END) > 0 THEN
            (1.0 - (SUM(CASE WHEN metric_name = 'integrity_failures' THEN metric_value::numeric ELSE 0 END)::numeric / 
                    SUM(CASE WHEN metric_name = 'files_checked' THEN metric_value::numeric ELSE 0 END)::numeric)) * 100
        ELSE 100
    END as integrity_success_rate_percent
FROM metrics
WHERE component = 'data'
  AND metric_name IN ('files_checked', 'integrity_failures')
  AND timestamp > NOW() - INTERVAL '24 hours';

-- Get integrity check results over time (last 7 days)
-- Returns: date, files_checked, integrity_failures, success_rate_percent
SELECT 
    DATE(timestamp) as date,
    SUM(CASE WHEN metric_name = 'files_checked' THEN metric_value::numeric ELSE 0 END) as files_checked,
    SUM(CASE WHEN metric_name = 'integrity_failures' THEN metric_value::numeric ELSE 0 END) as integrity_failures,
    CASE 
        WHEN SUM(CASE WHEN metric_name = 'files_checked' THEN metric_value::numeric ELSE 0 END) > 0 THEN
            (1.0 - (SUM(CASE WHEN metric_name = 'integrity_failures' THEN metric_value::numeric ELSE 0 END)::numeric / 
                    SUM(CASE WHEN metric_name = 'files_checked' THEN metric_value::numeric ELSE 0 END)::numeric)) * 100
        ELSE 100
    END as success_rate_percent
FROM metrics
WHERE component = 'data'
  AND metric_name IN ('files_checked', 'integrity_failures')
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY date
ORDER BY date DESC;

-- Get integrity failures by type (from alerts)
-- Returns: alert_type, failure_count, latest_failure_time
SELECT 
    alert_type,
    COUNT(*) as failure_count,
    MAX(created_at) as latest_failure_time
FROM alerts
WHERE component = 'DATA'
  AND alert_type LIKE '%integrity%'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY alert_type
ORDER BY failure_count DESC;

-- Get recent integrity failures
-- Returns: alert_level, alert_type, message, created_at
SELECT 
    alert_level,
    alert_type,
    message,
    created_at
FROM alerts
WHERE component = 'DATA'
  AND alert_type LIKE '%integrity%'
  AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- Get integrity check frequency
-- Returns: checks_per_day, avg_files_per_check
SELECT 
    COUNT(DISTINCT DATE(timestamp)) as checks_per_day,
    AVG(CASE WHEN metric_name = 'files_checked' THEN metric_value::numeric END) as avg_files_per_check
FROM metrics
WHERE component = 'data'
  AND metric_name = 'files_checked'
  AND timestamp > NOW() - INTERVAL '7 days';

-- Get integrity failure trend
-- Compare current day vs previous day
-- Returns: current_failures, previous_failures, trend
WITH current_period AS (
    SELECT SUM(metric_value::numeric) as failures
    FROM metrics
    WHERE component = 'data'
      AND metric_name = 'integrity_failures'
      AND timestamp > NOW() - INTERVAL '1 day'
),
previous_period AS (
    SELECT SUM(metric_value::numeric) as failures
    FROM metrics
    WHERE component = 'data'
      AND metric_name = 'integrity_failures'
      AND timestamp > NOW() - INTERVAL '2 days'
      AND timestamp <= NOW() - INTERVAL '1 day'
)
SELECT 
    cp.failures as current_failures,
    pp.failures as previous_failures,
    CASE 
        WHEN pp.failures > 0 THEN 
            ((cp.failures - pp.failures) / pp.failures * 100)
        ELSE 
            CASE WHEN cp.failures > 0 THEN 100 ELSE 0 END
    END as trend_percent
FROM current_period cp
CROSS JOIN previous_period pp;

-- Get backup file integrity correlation
-- Correlate backup freshness with integrity failures
-- Returns: backup_age_hours, integrity_failures, correlation
WITH backup_ages AS (
    SELECT 
        DATE_TRUNC('hour', timestamp) as hour,
        AVG(CASE WHEN metric_name = 'backup_newest_age_seconds' THEN metric_value::numeric / 3600 END) as backup_age_hours
    FROM metrics
    WHERE component = 'data'
      AND metric_name = 'backup_newest_age_seconds'
      AND timestamp > NOW() - INTERVAL '7 days'
    GROUP BY hour
),
integrity_checks AS (
    SELECT 
        DATE_TRUNC('hour', timestamp) as hour,
        SUM(CASE WHEN metric_name = 'integrity_failures' THEN metric_value::numeric ELSE 0 END) as failures
    FROM metrics
    WHERE component = 'data'
      AND metric_name = 'integrity_failures'
      AND timestamp > NOW() - INTERVAL '7 days'
    GROUP BY hour
)
SELECT 
    ba.backup_age_hours,
    ic.failures as integrity_failures,
    COUNT(*) as data_points
FROM backup_ages ba
LEFT JOIN integrity_checks ic ON ba.hour = ic.hour
WHERE ba.backup_age_hours IS NOT NULL
GROUP BY ba.backup_age_hours, ic.failures
ORDER BY ba.backup_age_hours DESC;

-- Get files with integrity issues (from metrics metadata if available)
-- Returns: file_path, failure_reason, check_time
-- Note: This is a template query - actual implementation depends on how file paths are stored
SELECT 
    metadata->>'file_path' as file_path,
    metadata->>'failure_reason' as failure_reason,
    timestamp as check_time
FROM metrics
WHERE component = 'data'
  AND metric_name = 'integrity_failures'
  AND metadata ? 'file_path'
  AND timestamp > NOW() - INTERVAL '7 days'
ORDER BY timestamp DESC;

