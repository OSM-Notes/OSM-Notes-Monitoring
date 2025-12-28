-- Infrastructure Connectivity Queries
-- Queries for monitoring network connectivity and service dependencies

-- Get current connectivity status
-- Returns: network_connectivity, connectivity_failures, connectivity_checks, timestamp
SELECT 
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'network_connectivity'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as network_connectivity,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'network_connectivity_failures'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as connectivity_failures,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'network_connectivity_checks'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as connectivity_checks,
    (
        SELECT MAX(timestamp) 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name IN ('network_connectivity', 'network_connectivity_failures', 'network_connectivity_checks')
    ) as timestamp;

-- Get service dependencies status
-- Returns: service_dependencies_available, service_dependencies_failures, service_dependencies_total
SELECT 
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'service_dependencies_available'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as service_dependencies_available,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'service_dependencies_failures'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as service_dependencies_failures,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'service_dependencies_total'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as service_dependencies_total;

-- Get database server health
-- Returns: database_uptime_seconds, database_active_connections, database_max_connections, connection_usage_percent
SELECT 
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'database_uptime_seconds'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as database_uptime_seconds,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'database_active_connections'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as database_active_connections,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'infrastructure' 
          AND m2.metric_name = 'database_max_connections'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as database_max_connections,
    CASE 
        WHEN (
            SELECT metric_value::numeric 
            FROM metrics m2 
            WHERE m2.component = 'infrastructure' 
              AND m2.metric_name = 'database_max_connections'
            ORDER BY timestamp DESC 
            LIMIT 1
        ) > 0 THEN
            (
                SELECT metric_value::numeric 
                FROM metrics m2 
                WHERE m2.component = 'infrastructure' 
                  AND m2.metric_name = 'database_active_connections'
                ORDER BY timestamp DESC 
                LIMIT 1
            ) * 100.0 / (
                SELECT metric_value::numeric 
                FROM metrics m2 
                WHERE m2.component = 'infrastructure' 
                  AND m2.metric_name = 'database_max_connections'
                ORDER BY timestamp DESC 
                LIMIT 1
            )
        ELSE 0
    END as connection_usage_percent;

-- Get connectivity alerts (last 7 days)
-- Returns: alert_type, alert_level, count, latest_alert_time
SELECT 
    alert_type,
    alert_level,
    COUNT(*) as count,
    MAX(created_at) as latest_alert_time
FROM alerts
WHERE component = 'INFRASTRUCTURE'
  AND alert_type IN ('network_connectivity_failure', 'service_dependency_failure', 'database_connection_failed', 'database_connections_high')
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY alert_type, alert_level
ORDER BY count DESC;

-- Get connectivity trend (last 7 days)
-- Returns: date, connectivity_success_rate, service_availability_rate
SELECT 
    DATE(timestamp) as date,
    AVG(CASE WHEN metric_name = 'network_connectivity' THEN metric_value::numeric END) * 100 as connectivity_success_rate,
    AVG(CASE WHEN metric_name = 'service_dependencies_available' THEN metric_value::numeric END) * 100 as service_availability_rate
FROM metrics
WHERE component = 'infrastructure'
  AND metric_name IN ('network_connectivity', 'service_dependencies_available')
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY date
ORDER BY date DESC;

-- Get database connection usage trend (last 24 hours)
-- Returns: hour, avg_active_connections, avg_max_connections, avg_usage_percent
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(CASE WHEN metric_name = 'database_active_connections' THEN metric_value::numeric END) as avg_active_connections,
    AVG(CASE WHEN metric_name = 'database_max_connections' THEN metric_value::numeric END) as avg_max_connections,
    CASE 
        WHEN AVG(CASE WHEN metric_name = 'database_max_connections' THEN metric_value::numeric END) > 0 THEN
            AVG(CASE WHEN metric_name = 'database_active_connections' THEN metric_value::numeric END) * 100.0 / 
            AVG(CASE WHEN metric_name = 'database_max_connections' THEN metric_value::numeric END)
        ELSE 0
    END as avg_usage_percent
FROM metrics
WHERE component = 'infrastructure'
  AND metric_name IN ('database_active_connections', 'database_max_connections')
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Get connectivity failures by time of day
-- Returns: hour_of_day, failure_count, total_checks, failure_rate_percent
SELECT 
    EXTRACT(HOUR FROM timestamp) as hour_of_day,
    SUM(CASE WHEN metric_name = 'network_connectivity_failures' THEN metric_value::numeric ELSE 0 END) as failure_count,
    SUM(CASE WHEN metric_name = 'network_connectivity_checks' THEN metric_value::numeric ELSE 0 END) as total_checks,
    CASE 
        WHEN SUM(CASE WHEN metric_name = 'network_connectivity_checks' THEN metric_value::numeric ELSE 0 END) > 0 THEN
            SUM(CASE WHEN metric_name = 'network_connectivity_failures' THEN metric_value::numeric ELSE 0 END) * 100.0 / 
            SUM(CASE WHEN metric_name = 'network_connectivity_checks' THEN metric_value::numeric ELSE 0 END)
        ELSE 0
    END as failure_rate_percent
FROM metrics
WHERE component = 'infrastructure'
  AND metric_name IN ('network_connectivity_failures', 'network_connectivity_checks')
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- Get service dependency failures over time
-- Returns: date, service_failures, service_total, availability_percent
SELECT 
    DATE(timestamp) as date,
    SUM(CASE WHEN metric_name = 'service_dependencies_failures' THEN metric_value::numeric ELSE 0 END) as service_failures,
    MAX(CASE WHEN metric_name = 'service_dependencies_total' THEN metric_value::numeric ELSE 0 END) as service_total,
    CASE 
        WHEN MAX(CASE WHEN metric_name = 'service_dependencies_total' THEN metric_value::numeric ELSE 0 END) > 0 THEN
            (1.0 - (SUM(CASE WHEN metric_name = 'service_dependencies_failures' THEN metric_value::numeric ELSE 0 END)::numeric / 
                    MAX(CASE WHEN metric_name = 'service_dependencies_total' THEN metric_value::numeric ELSE 0 END)::numeric)) * 100
        ELSE 100
    END as availability_percent
FROM metrics
WHERE component = 'infrastructure'
  AND metric_name IN ('service_dependencies_failures', 'service_dependencies_total')
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY date
ORDER BY date DESC;

