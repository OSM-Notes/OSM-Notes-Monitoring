-- WMS Service Status Queries
-- Queries for monitoring WMS service status and availability

-- Get current service availability status
-- Returns: availability (1=available, 0=unavailable), last_check_time, response_time_ms
SELECT
    metric_value::numeric AS availability,
    timestamp AS last_check_time,
    (
        SELECT metric_value::numeric
        FROM metrics
        WHERE metrics.component = 'wms'
              AND metrics.metric_name = 'service_response_time_ms'
              AND metrics.timestamp = (
              SELECT MAX(timestamp)
              FROM metrics
              WHERE metrics.component = 'wms'
                AND metrics.metric_name = 'service_response_time_ms'
              )
    ) AS response_time_ms
FROM metrics
WHERE component = 'wms'
      AND metric_name = 'service_availability'
ORDER BY timestamp DESC
LIMIT 1;

-- Get service availability over time (last 24 hours)
-- Returns: hour, availability_percent, avg_response_time_ms
SELECT
    DATE_TRUNC('hour', timestamp) AS hour,
    AVG(metric_value::numeric) * 100 AS availability_percent,
    (
        SELECT AVG(metrics.metric_value::numeric)
        FROM metrics
        WHERE metrics.component = 'wms'
              AND metrics.metric_name = 'service_response_time_ms'
              AND DATE_TRUNC(
              'hour', metrics.timestamp
              ) = DATE_TRUNC('hour', metrics.timestamp)
    ) AS avg_response_time_ms
FROM metrics
WHERE component = 'wms'
      AND metric_name = 'service_availability'
      AND timestamp > NOW() - interval '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Get current health status
-- Returns: health_status (1=healthy, 0=unhealthy), last_check_time, response_time_ms
SELECT
    metric_value::numeric AS health_status,
    timestamp AS last_check_time,
    (
        SELECT metric_value::numeric
        FROM metrics
        WHERE metrics.component = 'wms'
              AND metrics.metric_name = 'health_check_response_time_ms'
              AND metrics.timestamp = (
              SELECT MAX(timestamp)
              FROM metrics
              WHERE metrics.component = 'wms'
                AND metrics.metric_name = 'health_check_response_time_ms'
              )
    ) AS response_time_ms
FROM metrics
WHERE component = 'wms'
      AND metric_name = 'health_status'
ORDER BY timestamp DESC
LIMIT 1;

-- Get service uptime percentage (last 7 days)
-- Returns: uptime_percent, total_checks, available_checks
SELECT
    SUM(metric_value::numeric)::bigint AS available_checks,
    COUNT(*) AS total_checks,
    (
        SUM(metric_value::numeric)::numeric / COUNT(*)::numeric * 100
    ) AS uptime_percent
FROM metrics
WHERE component = 'wms'
      AND metric_name = 'service_availability'
      AND timestamp > NOW() - interval '7 days';

-- Get recent service outages
-- Returns: outage_start, outage_end, duration_seconds
WITH availability_changes AS (
    SELECT
        timestamp,
        metric_value::numeric AS availability,
        LAG(
            metric_value::numeric
        ) OVER (ORDER BY timestamp) AS prev_availability
    FROM metrics
    WHERE component = 'wms'
          AND metric_name = 'service_availability'
          AND timestamp > NOW() - interval '7 days'
    ORDER BY timestamp
),

outage_starts AS (
    SELECT timestamp AS outage_start
    FROM availability_changes
    WHERE
        availability = 0 AND (
            prev_availability IS NULL OR prev_availability = 1
        )
),

outage_ends AS (
    SELECT timestamp AS outage_end
    FROM availability_changes
    WHERE availability = 1 AND prev_availability = 0
)

SELECT
    outage_starts.outage_start,
    EXTRACT(
        EPOCH FROM (
            COALESCE(
                outage_ends.outage_end, CURRENT_TIMESTAMP
            ) - outage_starts.outage_start
        )
    )::bigint AS duration_seconds,
    COALESCE(outage_ends.outage_end, CURRENT_TIMESTAMP) AS outage_end
FROM outage_starts
    LEFT JOIN outage_ends ON outage_ends.outage_end > outage_starts.outage_start
ORDER BY outage_starts.outage_start DESC;
