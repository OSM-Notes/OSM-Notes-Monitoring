-- Optimized Data Freshness Queries for Ingestion Monitoring
-- Version: 1.0.0
-- Date: 2025-12-24
--
-- Optimized versions of data freshness queries
-- Assumes indexes from create_indexes.sql are created
-- See optimization_recommendations.md for details

-- Query 1: Last update timestamp for notes (OPTIMIZED)
-- Uses index on updated_at DESC
SELECT 
    MAX(updated_at) AS last_note_update,
    COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 hour') AS notes_updated_last_hour,
    COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '24 hours') AS notes_updated_last_24h,
    COUNT(*) AS total_notes
FROM notes
WHERE updated_at IS NOT NULL;  -- Helps index usage

-- Query 2: Last update timestamp for note comments (OPTIMIZED)
-- Uses index on created_at DESC
SELECT 
    MAX(created_at) AS last_comment_update,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 hour') AS comments_last_hour,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') AS comments_last_24h,
    COUNT(*) AS total_comments
FROM note_comments
WHERE created_at IS NOT NULL;  -- Helps index usage

-- Query 3: Data freshness summary (OPTIMIZED)
-- Uses indexes and filters NULL values
SELECT 
    'notes' AS table_name,
    MAX(updated_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS age_seconds,
    COUNT(*) AS total_records
FROM notes
WHERE updated_at IS NOT NULL
UNION ALL
SELECT 
    'note_comments' AS table_name,
    MAX(created_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) AS age_seconds,
    COUNT(*) AS total_records
FROM note_comments
WHERE created_at IS NOT NULL
UNION ALL
SELECT 
    'note_comment_texts' AS table_name,
    MAX(created_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) AS age_seconds,
    COUNT(*) AS total_records
FROM note_comment_texts
WHERE created_at IS NOT NULL
ORDER BY age_seconds DESC;

-- Query 4: Notes by update frequency (OPTIMIZED)
-- Uses partial index for recent updates
SELECT 
    CASE 
        WHEN updated_at > NOW() - INTERVAL '1 hour' THEN 'Last Hour'
        WHEN updated_at > NOW() - INTERVAL '24 hours' THEN 'Last 24 Hours'
        WHEN updated_at > NOW() - INTERVAL '7 days' THEN 'Last Week'
        WHEN updated_at > NOW() - INTERVAL '30 days' THEN 'Last Month'
        ELSE 'Older'
    END AS update_period,
    COUNT(*) AS note_count,
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM notes), 0), 2) AS percentage
FROM notes
WHERE updated_at IS NOT NULL
GROUP BY update_period
ORDER BY 
    CASE update_period
        WHEN 'Last Hour' THEN 1
        WHEN 'Last 24 Hours' THEN 2
        WHEN 'Last Week' THEN 3
        WHEN 'Last Month' THEN 4
        ELSE 5
    END;

-- Query 5: Stale data detection (OPTIMIZED)
-- Uses index on updated_at with WHERE clause
SELECT 
    COUNT(*) AS stale_notes_count,
    MIN(updated_at) AS oldest_update,
    MAX(updated_at) AS newest_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS max_age_seconds
FROM notes
WHERE updated_at < NOW() - INTERVAL '24 hours'
  AND updated_at IS NOT NULL;

-- Query 6: Recent activity summary (OPTIMIZED)
-- Uses index on updated_at DESC, limits to recent data
SELECT 
    DATE_TRUNC('hour', updated_at) AS hour,
    COUNT(*) AS notes_updated,
    COUNT(DISTINCT note_id) AS unique_notes
FROM notes
WHERE updated_at > NOW() - INTERVAL '24 hours'
  AND updated_at IS NOT NULL
GROUP BY DATE_TRUNC('hour', updated_at)
ORDER BY hour DESC
LIMIT 24;

