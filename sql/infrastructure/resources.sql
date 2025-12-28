-- Infrastructure Resources Queries
-- Queries for monitoring server resources (CPU, memory, disk)

-- Get current server resource usage
-- Returns: cpu_usage_percent, memory_usage_percent, disk_usage_percent, timestamp
SELECT 
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'cpu_usage_percent'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as cpu_usage_percent,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'memory_usage_percent'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as memory_usage_percent,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'disk_usage_percent'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as disk_usage_percent,
    (
        SELECT MAX(timestamp) 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name IN ('cpu_usage_percent', 'memory_usage_percent', 'disk_usage_percent')
    ) as timestamp;

-- Get resource usage trend (last 24 hours)
-- Returns: hour, avg_cpu_percent, avg_memory_percent, avg_disk_percent
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(CASE WHEN metric_name = 'cpu_usage_percent' THEN metric_value::numeric END) as avg_cpu_percent,
    AVG(CASE WHEN metric_name = 'memory_usage_percent' THEN metric_value::numeric END) as avg_memory_percent,
    AVG(CASE WHEN metric_name = 'disk_usage_percent' THEN metric_value::numeric END) as avg_disk_percent
FROM metrics
WHERE component = 'infrastructure'
  AND metric_name IN ('cpu_usage_percent', 'memory_usage_percent', 'disk_usage_percent')
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Get memory details
-- Returns: memory_total_bytes, memory_available_bytes, memory_usage_percent
SELECT 
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'memory_total_bytes'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as memory_total_bytes,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'memory_available_bytes'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as memory_available_bytes,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'memory_usage_percent'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as memory_usage_percent;

-- Get disk details
-- Returns: disk_total_bytes, disk_available_bytes, disk_usage_percent
SELECT 
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'disk_total_bytes'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as disk_total_bytes,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'disk_available_bytes'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as disk_available_bytes,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'disk_usage_percent'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as disk_usage_percent;

-- Get resource usage alerts (last 7 days)
-- Returns: alert_type, alert_level, count, latest_alert_time
SELECT 
    alert_type,
    alert_level,
    COUNT(*) as count,
    MAX(created_at) as latest_alert_time
FROM alerts
WHERE component = 'INFRASTRUCTURE'
  AND alert_type IN ('cpu_usage_high', 'memory_usage_high', 'disk_usage_high')
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY alert_type, alert_level
ORDER BY count DESC;

-- Get resource usage statistics (last 7 days)
-- Returns: resource_type, min_usage, max_usage, avg_usage, threshold_exceeded_count
SELECT 
    CASE 
        WHEN metric_name = 'cpu_usage_percent' THEN 'CPU'
        WHEN metric_name = 'memory_usage_percent' THEN 'Memory'
        WHEN metric_name = 'disk_usage_percent' THEN 'Disk'
        ELSE metric_name
    END as resource_type,
    MIN(metric_value::numeric) as min_usage,
    MAX(metric_value::numeric) as max_usage,
    AVG(metric_value::numeric) as avg_usage,
    COUNT(CASE WHEN metric_value::numeric > 
        CASE 
            WHEN metric_name = 'cpu_usage_percent' THEN 80
            WHEN metric_name = 'memory_usage_percent' THEN 85
            WHEN metric_name = 'disk_usage_percent' THEN 90
            ELSE 0
        END
    THEN 1 END) as threshold_exceeded_count
FROM metrics
WHERE component = 'infrastructure'
  AND metric_name IN ('cpu_usage_percent', 'memory_usage_percent', 'disk_usage_percent')
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY resource_type, metric_name
ORDER BY resource_type;

-- Get resource usage peaks (top 10)
-- Returns: timestamp, cpu_usage, memory_usage, disk_usage
WITH resource_data AS (
    SELECT 
        timestamp,
        MAX(CASE WHEN metric_name = 'cpu_usage_percent' THEN metric_value::numeric END) as cpu_usage,
        MAX(CASE WHEN metric_name = 'memory_usage_percent' THEN metric_value::numeric END) as memory_usage,
        MAX(CASE WHEN metric_name = 'disk_usage_percent' THEN metric_value::numeric END) as disk_usage
    FROM metrics
    WHERE component = 'infrastructure'
      AND metric_name IN ('cpu_usage_percent', 'memory_usage_percent', 'disk_usage_percent')
      AND timestamp > NOW() - INTERVAL '7 days'
    GROUP BY timestamp
)
SELECT 
    timestamp,
    cpu_usage,
    memory_usage,
    disk_usage,
    (cpu_usage + memory_usage + disk_usage) / 3 as avg_resource_usage
FROM resource_data
ORDER BY avg_resource_usage DESC
LIMIT 10;

-- Get resource capacity planning data (last 30 days)
-- Returns: date, avg_cpu, avg_memory, avg_disk, max_cpu, max_memory, max_disk
SELECT 
    DATE(timestamp) as date,
    AVG(CASE WHEN metric_name = 'cpu_usage_percent' THEN metric_value::numeric END) as avg_cpu,
    AVG(CASE WHEN metric_name = 'memory_usage_percent' THEN metric_value::numeric END) as avg_memory,
    AVG(CASE WHEN metric_name = 'disk_usage_percent' THEN metric_value::numeric END) as avg_disk,
    MAX(CASE WHEN metric_name = 'cpu_usage_percent' THEN metric_value::numeric END) as max_cpu,
    MAX(CASE WHEN metric_name = 'memory_usage_percent' THEN metric_value::numeric END) as max_memory,
    MAX(CASE WHEN metric_name = 'disk_usage_percent' THEN metric_value::numeric END) as max_disk
FROM metrics
WHERE component = 'infrastructure'
  AND metric_name IN ('cpu_usage_percent', 'memory_usage_percent', 'disk_usage_percent')
  AND timestamp > NOW() - INTERVAL '30 days'
GROUP BY date
ORDER BY date DESC;

