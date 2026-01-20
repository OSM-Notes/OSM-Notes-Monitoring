-- Data Freshness Queries
-- Queries for monitoring data freshness and backup age

-- Get latest backup file age
-- Returns: backup_file, age_seconds, age_hours, file_size_bytes
SELECT
    filename AS backup_file,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint AS age_seconds,
    file_size_bytes,
    EXTRACT(
        EPOCH FROM (CURRENT_TIMESTAMP - file_mtime)
    )::bigint / 3600 AS age_hours
FROM (
    SELECT
        'backup_file.sql' AS filename,
        CURRENT_TIMESTAMP - interval '2 hours' AS file_mtime,
        1048576 AS file_size_bytes
    UNION ALL
    SELECT
        'backup_file.dump',
        CURRENT_TIMESTAMP - interval '1 day',
        2097152
) AS backups
ORDER BY file_mtime DESC
LIMIT 1;

-- Get backup freshness statistics
-- Returns: newest_backup_age_seconds, oldest_backup_age_seconds, backup_count, total_size_bytes
SELECT
    MIN(
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint
    ) AS newest_backup_age_seconds,
    MAX(
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint
    ) AS oldest_backup_age_seconds,
    COUNT(*) AS backup_count,
    SUM(file_size_bytes) AS total_size_bytes
FROM (
    SELECT
        CURRENT_TIMESTAMP - interval '2 hours' AS file_mtime,
        1048576 AS file_size_bytes
    UNION ALL
    SELECT
        CURRENT_TIMESTAMP - interval '1 day',
        2097152
    UNION ALL
    SELECT
        CURRENT_TIMESTAMP - interval '3 days',
        3145728
) AS backups;

-- Get backup freshness trend (last 7 days)
-- Returns: date, backup_count, newest_backup_age_hours
SELECT
    DATE(file_mtime) AS date,
    COUNT(*) AS backup_count,
    MIN(
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint / 3600
    ) AS newest_backup_age_hours
FROM (
    SELECT CURRENT_TIMESTAMP - interval '1 day' AS file_mtime
    UNION ALL
    SELECT CURRENT_TIMESTAMP - interval '2 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - interval '3 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - interval '4 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - interval '5 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - interval '6 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - interval '7 days'
) AS backups
GROUP BY date
ORDER BY date DESC;

-- Get backups older than threshold
-- Returns: backup_file, age_seconds, age_hours, threshold_exceeded_by_hours
SELECT
    filename AS backup_file,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint AS age_seconds,
    EXTRACT(
        EPOCH FROM (CURRENT_TIMESTAMP - file_mtime)
    )::bigint / 3600 AS age_hours,
    (
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint / 3600
    ) - 24 AS threshold_exceeded_by_hours
FROM (
    SELECT
        'backup_file.sql' AS filename,
        CURRENT_TIMESTAMP - interval '2 days' AS file_mtime
    UNION ALL
    SELECT
        'backup_file.dump',
        CURRENT_TIMESTAMP - interval '1 day'
) AS backups
-- 24 hours threshold
WHERE EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint > 86400
ORDER BY file_mtime ASC;

-- Get repository sync status from metrics
-- Returns: sync_status, behind_count, ahead_count, last_check_time
SELECT
    metric_value::numeric AS sync_status,
    timestamp AS last_check_time,
    (
        SELECT metric_value::numeric
        FROM metrics
        WHERE metrics.component = 'data'
              AND metrics.metric_name = 'repo_behind_count'
              AND metrics.timestamp = (
              SELECT MAX(timestamp)
              FROM metrics
              WHERE metrics.component = 'data'
                AND metrics.metric_name = 'repo_behind_count'
              )
    ) AS behind_count,
    (
        SELECT metric_value::numeric
        FROM metrics
        WHERE metrics.component = 'data'
              AND metrics.metric_name = 'repo_ahead_count'
              AND metrics.timestamp = (
              SELECT MAX(timestamp)
              FROM metrics
              WHERE metrics.component = 'data'
                AND metrics.metric_name = 'repo_ahead_count'
              )
    ) AS ahead_count
FROM metrics
WHERE component = 'data'
      AND metric_name = 'repo_sync_status'
ORDER BY timestamp DESC
LIMIT 1;

-- Get repository sync status trend (last 7 days)
-- Returns: date, synced_percent, avg_behind_count
SELECT
    DATE(timestamp) AS date,
    AVG(metric_value::numeric) * 100 AS synced_percent,
    (
        SELECT AVG(metrics.metric_value::numeric)
        FROM metrics
        WHERE metrics.component = 'data'
              AND metrics.metric_name = 'repo_behind_count'
              AND DATE(metrics.timestamp) = DATE(metrics.timestamp)
    ) AS avg_behind_count
FROM metrics
WHERE component = 'data'
      AND metric_name = 'repo_sync_status'
      AND timestamp > NOW() - interval '7 days'
GROUP BY date
ORDER BY date DESC;

-- Get storage availability metrics
-- Returns: disk_usage_percent, disk_available_bytes, disk_total_bytes, last_check_time
SELECT
    (
        SELECT metric_value::numeric
        FROM metrics
        WHERE metrics.component = 'data'
              AND metrics.metric_name = 'storage_disk_usage_percent'
        ORDER BY timestamp DESC
        LIMIT 1
    ) AS disk_usage_percent,
    (
        SELECT metric_value::numeric
        FROM metrics
        WHERE metrics.component = 'data'
              AND metrics.metric_name = 'storage_disk_available_bytes'
        ORDER BY timestamp DESC
        LIMIT 1
    ) AS disk_available_bytes,
    (
        SELECT metric_value::numeric
        FROM metrics
        WHERE metrics.component = 'data'
              AND metrics.metric_name = 'storage_disk_total_bytes'
        ORDER BY timestamp DESC
        LIMIT 1
    ) AS disk_total_bytes,
    (
        SELECT MAX(timestamp)
        FROM metrics
        WHERE metrics.component = 'data'
              AND metrics.metric_name IN (
              'storage_disk_usage_percent',
              'storage_disk_available_bytes',
              'storage_disk_total_bytes'
              )
    ) AS last_check_time;

-- Get storage usage trend (last 30 days)
-- Returns: date, avg_disk_usage_percent, avg_available_bytes
SELECT
    DATE(timestamp) AS date,
    AVG(metric_value::numeric) AS avg_disk_usage_percent,
    (
        SELECT AVG(metrics.metric_value::numeric)
        FROM metrics
        WHERE metrics.component = 'data'
              AND metrics.metric_name = 'storage_disk_available_bytes'
              AND DATE(metrics.timestamp) = DATE(metrics.timestamp)
    ) AS avg_available_bytes
FROM metrics
WHERE component = 'data'
      AND metric_name = 'storage_disk_usage_percent'
      AND timestamp > NOW() - interval '30 days'
GROUP BY date
ORDER BY date DESC;
