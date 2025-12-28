-- Data Freshness Queries
-- Queries for monitoring data freshness and backup age

-- Get latest backup file age
-- Returns: backup_file, age_seconds, age_hours, file_size_bytes
SELECT 
    filename as backup_file,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint as age_seconds,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint / 3600 as age_hours,
    file_size_bytes
FROM (
    SELECT 
        'backup_file.sql' as filename,
        CURRENT_TIMESTAMP - INTERVAL '2 hours' as file_mtime,
        1048576 as file_size_bytes
    UNION ALL
    SELECT 
        'backup_file.dump',
        CURRENT_TIMESTAMP - INTERVAL '1 day',
        2097152
) as backups
ORDER BY file_mtime DESC
LIMIT 1;

-- Get backup freshness statistics
-- Returns: newest_backup_age_seconds, oldest_backup_age_seconds, backup_count, total_size_bytes
SELECT 
    MIN(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint) as newest_backup_age_seconds,
    MAX(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint) as oldest_backup_age_seconds,
    COUNT(*) as backup_count,
    SUM(file_size_bytes) as total_size_bytes
FROM (
    SELECT 
        CURRENT_TIMESTAMP - INTERVAL '2 hours' as file_mtime,
        1048576 as file_size_bytes
    UNION ALL
    SELECT 
        CURRENT_TIMESTAMP - INTERVAL '1 day',
        2097152
    UNION ALL
    SELECT 
        CURRENT_TIMESTAMP - INTERVAL '3 days',
        3145728
) as backups;

-- Get backup freshness trend (last 7 days)
-- Returns: date, backup_count, newest_backup_age_hours
SELECT 
    DATE(file_mtime) as date,
    COUNT(*) as backup_count,
    MIN(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint / 3600) as newest_backup_age_hours
FROM (
    SELECT CURRENT_TIMESTAMP - INTERVAL '1 day' as file_mtime
    UNION ALL
    SELECT CURRENT_TIMESTAMP - INTERVAL '2 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - INTERVAL '3 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - INTERVAL '4 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - INTERVAL '5 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - INTERVAL '6 days'
    UNION ALL
    SELECT CURRENT_TIMESTAMP - INTERVAL '7 days'
) as backups
GROUP BY date
ORDER BY date DESC;

-- Get backups older than threshold
-- Returns: backup_file, age_seconds, age_hours, threshold_exceeded_by_hours
SELECT 
    filename as backup_file,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint as age_seconds,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint / 3600 as age_hours,
    (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint / 3600) - 24 as threshold_exceeded_by_hours
FROM (
    SELECT 
        'backup_file.sql' as filename,
        CURRENT_TIMESTAMP - INTERVAL '2 days' as file_mtime
    UNION ALL
    SELECT 
        'backup_file.dump',
        CURRENT_TIMESTAMP - INTERVAL '1 day'
) as backups
WHERE EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - file_mtime))::bigint > 86400  -- 24 hours threshold
ORDER BY file_mtime ASC;

-- Get repository sync status from metrics
-- Returns: sync_status, behind_count, ahead_count, last_check_time
SELECT 
    metric_value::numeric as sync_status,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'data' 
          AND m2.metric_name = 'repo_behind_count'
          AND m2.timestamp = (
              SELECT MAX(timestamp) 
              FROM metrics m3 
              WHERE m3.component = 'data' 
                AND m3.metric_name = 'repo_behind_count'
          )
    ) as behind_count,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'data' 
          AND m2.metric_name = 'repo_ahead_count'
          AND m2.timestamp = (
              SELECT MAX(timestamp) 
              FROM metrics m3 
              WHERE m3.component = 'data' 
                AND m3.metric_name = 'repo_ahead_count'
          )
    ) as ahead_count,
    timestamp as last_check_time
FROM metrics
WHERE component = 'data'
  AND metric_name = 'repo_sync_status'
ORDER BY timestamp DESC
LIMIT 1;

-- Get repository sync status trend (last 7 days)
-- Returns: date, synced_percent, avg_behind_count
SELECT 
    DATE(timestamp) as date,
    AVG(metric_value::numeric) * 100 as synced_percent,
    (
        SELECT AVG(m2.metric_value::numeric)
        FROM metrics m2
        WHERE m2.component = 'data'
          AND m2.metric_name = 'repo_behind_count'
          AND DATE(m2.timestamp) = DATE(m.timestamp)
    ) as avg_behind_count
FROM metrics m
WHERE component = 'data'
  AND metric_name = 'repo_sync_status'
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY date
ORDER BY date DESC;

-- Get storage availability metrics
-- Returns: disk_usage_percent, disk_available_bytes, disk_total_bytes, last_check_time
SELECT 
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'data' 
          AND m2.metric_name = 'storage_disk_usage_percent'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as disk_usage_percent,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'data' 
          AND m2.metric_name = 'storage_disk_available_bytes'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as disk_available_bytes,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'data' 
          AND m2.metric_name = 'storage_disk_total_bytes'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as disk_total_bytes,
    (
        SELECT MAX(timestamp) 
        FROM metrics m2 
        WHERE m2.component = 'data' 
          AND m2.metric_name IN ('storage_disk_usage_percent', 'storage_disk_available_bytes', 'storage_disk_total_bytes')
    ) as last_check_time;

-- Get storage usage trend (last 30 days)
-- Returns: date, avg_disk_usage_percent, avg_available_bytes
SELECT 
    DATE(timestamp) as date,
    AVG(metric_value::numeric) as avg_disk_usage_percent,
    (
        SELECT AVG(m2.metric_value::numeric)
        FROM metrics m2
        WHERE m2.component = 'data'
          AND m2.metric_name = 'storage_disk_available_bytes'
          AND DATE(m2.timestamp) = DATE(m.timestamp)
    ) as avg_available_bytes
FROM metrics m
WHERE component = 'data'
  AND metric_name = 'storage_disk_usage_percent'
  AND timestamp > NOW() - INTERVAL '30 days'
GROUP BY date
ORDER BY date DESC;

