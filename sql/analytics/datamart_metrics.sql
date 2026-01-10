-- Datamart Metrics for Analytics Monitoring
-- Version: 1.0.0
-- Date: 2026-01-09
--
-- These queries retrieve datamart metrics from PostgreSQL
-- for the Analytics data warehouse (schema 'dwh').

-- Query 1: Datamart Freshness (Time since last update)
-- Provides the time since last update for each datamart table
SELECT
    'datamart_countries' AS datamart_name,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint AS freshness_seconds,
    MAX(updated_at) AS last_update_timestamp
FROM dwh.datamart_countries
WHERE updated_at IS NOT NULL

UNION ALL

SELECT
    'datamart_users' AS datamart_name,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint AS freshness_seconds,
    MAX(updated_at) AS last_update_timestamp
FROM dwh.datamart_users
WHERE updated_at IS NOT NULL

UNION ALL

SELECT
    'datamart_global' AS datamart_name,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint AS freshness_seconds,
    MAX(updated_at) AS last_update_timestamp
FROM dwh.datamart_global
WHERE updated_at IS NOT NULL;

-- Query 2: Record Counts by Datamart
-- Provides the total number of records in each datamart table
SELECT
    'datamart_countries' AS datamart_name,
    COUNT(*) AS record_count
FROM dwh.datamart_countries

UNION ALL

SELECT
    'datamart_users' AS datamart_name,
    COUNT(*) AS record_count
FROM dwh.datamart_users

UNION ALL

SELECT
    'datamart_global' AS datamart_name,
    COUNT(*) AS record_count
FROM dwh.datamart_global;

-- Query 3: Datamart Growth (Records added in last 24 hours)
-- Shows how many records were added to each datamart in the last 24 hours
SELECT
    'datamart_countries' AS datamart_name,
    COUNT(*) AS records_added_24h
FROM dwh.datamart_countries
WHERE created_at >= NOW() - INTERVAL '24 hours'

UNION ALL

SELECT
    'datamart_users' AS datamart_name,
    COUNT(*) AS records_added_24h
FROM dwh.datamart_users
WHERE created_at >= NOW() - INTERVAL '24 hours'

UNION ALL

SELECT
    'datamart_global' AS datamart_name,
    COUNT(*) AS records_added_24h
FROM dwh.datamart_global
WHERE created_at >= NOW() - INTERVAL '24 hours';

-- Query 4: Obsolete Datamarts Detection (> 24 hours since last update)
-- Identifies datamarts that haven't been updated in more than 24 hours
SELECT
    'datamart_countries' AS datamart_name,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint AS freshness_seconds,
    MAX(updated_at) AS last_update_timestamp,
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint > 86400 THEN 1
        ELSE 0
    END AS is_obsolete
FROM dwh.datamart_countries
WHERE updated_at IS NOT NULL

UNION ALL

SELECT
    'datamart_users' AS datamart_name,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint AS freshness_seconds,
    MAX(updated_at) AS last_update_timestamp,
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint > 86400 THEN 1
        ELSE 0
    END AS is_obsolete
FROM dwh.datamart_users
WHERE updated_at IS NOT NULL

UNION ALL

SELECT
    'datamart_global' AS datamart_name,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint AS freshness_seconds,
    MAX(updated_at) AS last_update_timestamp,
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint > 86400 THEN 1
        ELSE 0
    END AS is_obsolete
FROM dwh.datamart_global
WHERE updated_at IS NOT NULL;

-- Query 5: Datamart Update Frequency
-- Shows how many updates occurred in the last 7 days per datamart
SELECT
    'datamart_countries' AS datamart_name,
    COUNT(DISTINCT DATE(updated_at)) AS update_days_count,
    COUNT(*) AS total_updates_count
FROM dwh.datamart_countries
WHERE updated_at >= NOW() - INTERVAL '7 days'
  AND updated_at IS NOT NULL

UNION ALL

SELECT
    'datamart_users' AS datamart_name,
    COUNT(DISTINCT DATE(updated_at)) AS update_days_count,
    COUNT(*) AS total_updates_count
FROM dwh.datamart_users
WHERE updated_at >= NOW() - INTERVAL '7 days'
  AND updated_at IS NOT NULL

UNION ALL

SELECT
    'datamart_global' AS datamart_name,
    COUNT(DISTINCT DATE(updated_at)) AS update_days_count,
    COUNT(*) AS total_updates_count
FROM dwh.datamart_global
WHERE updated_at >= NOW() - INTERVAL '7 days'
  AND updated_at IS NOT NULL;

-- Query 6: Datamart Table Sizes
-- Provides the size of each datamart table
SELECT
    'datamart_countries' AS datamart_name,
    pg_size_pretty(pg_total_relation_size('dwh.datamart_countries')) AS total_size,
    pg_total_relation_size('dwh.datamart_countries') AS total_size_bytes,
    pg_size_pretty(pg_relation_size('dwh.datamart_countries')) AS table_size,
    pg_relation_size('dwh.datamart_countries') AS table_size_bytes

UNION ALL

SELECT
    'datamart_users' AS datamart_name,
    pg_size_pretty(pg_total_relation_size('dwh.datamart_users')) AS total_size,
    pg_total_relation_size('dwh.datamart_users') AS total_size_bytes,
    pg_size_pretty(pg_relation_size('dwh.datamart_users')) AS table_size,
    pg_relation_size('dwh.datamart_users') AS table_size_bytes

UNION ALL

SELECT
    'datamart_global' AS datamart_name,
    pg_size_pretty(pg_total_relation_size('dwh.datamart_global')) AS total_size,
    pg_total_relation_size('dwh.datamart_global') AS total_size_bytes,
    pg_size_pretty(pg_relation_size('dwh.datamart_global')) AS table_size,
    pg_relation_size('dwh.datamart_global') AS table_size_bytes;

-- Query 7: Datamart Countries Specific Metrics
-- Provides metrics specific to datamart_countries (if applicable)
SELECT
    COUNT(*) AS total_countries,
    COUNT(DISTINCT country_code) AS unique_countries,
    MIN(updated_at) AS oldest_update,
    MAX(updated_at) AS newest_update
FROM dwh.datamart_countries;

-- Query 8: Datamart Users Specific Metrics
-- Provides metrics specific to datamart_users (if applicable)
SELECT
    COUNT(*) AS total_users,
    COUNT(DISTINCT user_id) AS unique_users,
    MIN(updated_at) AS oldest_update,
    MAX(updated_at) AS newest_update
FROM dwh.datamart_users;

-- Query 9: Datamart Update Gaps Detection
-- Detects gaps in datamart updates (more than expected interval)
-- Expected: daily updates, so gaps > 25 hours are suspicious
SELECT
    'datamart_countries' AS datamart_name,
    MAX(updated_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint / 3600 AS hours_since_update,
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint > 90000 THEN 1
        ELSE 0
    END AS has_gap
FROM dwh.datamart_countries
WHERE updated_at IS NOT NULL

UNION ALL

SELECT
    'datamart_users' AS datamart_name,
    MAX(updated_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint / 3600 AS hours_since_update,
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint > 90000 THEN 1
        ELSE 0
    END AS has_gap
FROM dwh.datamart_users
WHERE updated_at IS NOT NULL

UNION ALL

SELECT
    'datamart_global' AS datamart_name,
    MAX(updated_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint / 3600 AS hours_since_update,
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(updated_at)))::bigint > 90000 THEN 1
        ELSE 0
    END AS has_gap
FROM dwh.datamart_global
WHERE updated_at IS NOT NULL;
