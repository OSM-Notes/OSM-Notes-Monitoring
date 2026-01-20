-- Data Integrity Queries
-- Queries for monitoring file integrity and data validation

-- Get file integrity statistics
-- Returns: files_checked, integrity_failures, integrity_success_rate_percent
SELECT
    SUM(
        CASE
            WHEN metric_name = 'files_checked' THEN metric_value::numeric ELSE 0
        END
    ) AS files_checked,
    SUM(
        CASE
            WHEN
                metric_name = 'integrity_failures' THEN metric_value::numeric
            ELSE 0
        END
    ) AS integrity_failures,
    CASE
        WHEN
            SUM(
                CASE
                    WHEN
                        metric_name = 'files_checked' THEN metric_value::numeric
                    ELSE 0
                END
            ) > 0 THEN
            (
                1.0 - (
                    SUM(
                        CASE
                            WHEN
                                metric_name = 'integrity_failures' THEN metric_value::numeric
                            ELSE 0
                        END
                    )::numeric
                    / SUM(
                        CASE
                            WHEN
                                metric_name = 'files_checked' THEN metric_value::numeric
                            ELSE 0
                        END
                    )::numeric
                )) * 100
        ELSE 100
    END AS integrity_success_rate_percent
FROM metrics
WHERE component = 'data'
      AND metric_name IN ('files_checked', 'integrity_failures')
      AND timestamp > NOW() - interval '24 hours';

-- Get integrity check results over time (last 7 days)
-- Returns: date, files_checked, integrity_failures, success_rate_percent
SELECT
    DATE(timestamp) AS date,
    SUM(
        CASE
            WHEN metric_name = 'files_checked' THEN metric_value::numeric ELSE 0
        END
    ) AS files_checked,
    SUM(
        CASE
            WHEN
                metric_name = 'integrity_failures' THEN metric_value::numeric
            ELSE 0
        END
    ) AS integrity_failures,
    CASE
        WHEN
            SUM(
                CASE
                    WHEN
                        metric_name = 'files_checked' THEN metric_value::numeric
                    ELSE 0
                END
            ) > 0 THEN
            (
                1.0 - (
                    SUM(
                        CASE
                            WHEN
                                metric_name = 'integrity_failures' THEN metric_value::numeric
                            ELSE 0
                        END
                    )::numeric
                    / SUM(
                        CASE
                            WHEN
                                metric_name = 'files_checked' THEN metric_value::numeric
                            ELSE 0
                        END
                    )::numeric
                )) * 100
        ELSE 100
    END AS success_rate_percent
FROM metrics
WHERE component = 'data'
      AND metric_name IN ('files_checked', 'integrity_failures')
      AND timestamp > NOW() - interval '7 days'
GROUP BY date
ORDER BY date DESC;

-- Get integrity failures by type (from alerts)
-- Returns: alert_type, failure_count, latest_failure_time
SELECT
    alert_type,
    COUNT(*) AS failure_count,
    MAX(created_at) AS latest_failure_time
FROM alerts
WHERE component = 'DATA'
      AND alert_type LIKE '%integrity%'
      AND created_at > NOW() - interval '7 days'
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
      AND created_at > NOW() - interval '24 hours'
ORDER BY created_at DESC;

-- Get integrity check frequency
-- Returns: checks_per_day, avg_files_per_check
SELECT
    COUNT(DISTINCT DATE(timestamp)) AS checks_per_day,
    AVG(
        CASE WHEN metric_name = 'files_checked' THEN metric_value::numeric END
    ) AS avg_files_per_check
FROM metrics
WHERE component = 'data'
      AND metric_name = 'files_checked'
      AND timestamp > NOW() - interval '7 days';

-- Get integrity failure trend
-- Compare current day vs previous day
-- Returns: current_failures, previous_failures, trend
WITH current_period AS (
    SELECT SUM(metric_value::numeric) AS failures
    FROM metrics
    WHERE component = 'data'
          AND metric_name = 'integrity_failures'
          AND timestamp > NOW() - interval '1 day'
),

previous_period AS (
    SELECT SUM(metric_value::numeric) AS failures
    FROM metrics
    WHERE component = 'data'
          AND metric_name = 'integrity_failures'
          AND timestamp > NOW() - interval '2 days'
          AND timestamp <= NOW() - interval '1 day'
)

SELECT
    current_period.failures AS current_failures,
    previous_period.failures AS previous_failures,
    CASE
        WHEN previous_period.failures > 0 THEN
            (
                (
                    current_period.failures - previous_period.failures
                ) / previous_period.failures * 100
            )
        WHEN current_period.failures > 0 THEN 100
        ELSE 0
    END AS trend_percent
FROM current_period
    CROSS JOIN previous_period;

-- Get backup file integrity correlation
-- Correlate backup freshness with integrity failures
-- Returns: backup_age_hours, integrity_failures, correlation
WITH backup_ages AS (
    SELECT
        DATE_TRUNC('hour', timestamp) AS hour,
        AVG(
            CASE
                WHEN
                    metric_name = 'backup_newest_age_seconds' THEN metric_value::numeric / 3600
            END
        ) AS backup_age_hours
    FROM metrics
    WHERE component = 'data'
          AND metric_name = 'backup_newest_age_seconds'
          AND timestamp > NOW() - interval '7 days'
    GROUP BY hour
),

integrity_checks AS (
    SELECT
        DATE_TRUNC('hour', timestamp) AS hour,
        SUM(
            CASE
                WHEN
                    metric_name = 'integrity_failures' THEN metric_value::numeric
                ELSE 0
            END
        ) AS failures
    FROM metrics
    WHERE component = 'data'
          AND metric_name = 'integrity_failures'
          AND timestamp > NOW() - interval '7 days'
    GROUP BY hour
)

SELECT
    backup_ages.backup_age_hours,
    integrity_checks.failures AS integrity_failures,
    COUNT(*) AS data_points
FROM backup_ages
    LEFT JOIN integrity_checks ON backup_ages.hour = integrity_checks.hour
WHERE backup_ages.backup_age_hours IS NOT NULL
GROUP BY backup_ages.backup_age_hours, integrity_checks.failures
ORDER BY backup_ages.backup_age_hours DESC;

-- Get files with integrity issues (from metrics metadata if available)
-- Returns: file_path, failure_reason, check_time
-- Note: This is a template query - actual implementation depends on how file paths are stored
SELECT
    timestamp AS check_time,
    metadata ->> 'file_path' AS file_path,
    metadata ->> 'failure_reason' AS failure_reason
FROM metrics
WHERE component = 'data'
      AND metric_name = 'integrity_failures'
      AND metadata ? 'file_path'
      AND timestamp > NOW() - interval '7 days'
ORDER BY timestamp DESC;
