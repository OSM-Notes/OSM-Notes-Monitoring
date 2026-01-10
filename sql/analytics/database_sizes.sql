-- Database Sizes Metrics for Analytics Monitoring
-- Version: 1.0.0
-- Date: 2026-01-09
--
-- These queries retrieve database size metrics from PostgreSQL
-- for the Analytics data warehouse (schema 'dwh').

-- Query 1: Total Schema Size
-- Provides the total size of the dwh schema
SELECT
    schemaname,
    pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename))) AS total_size,
    SUM(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size_bytes
FROM pg_tables
WHERE schemaname = 'dwh'
GROUP BY schemaname;

-- Query 2: Table Sizes (All Tables in dwh Schema)
-- Lists all tables in the dwh schema ordered by size
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS indexes_size,
    (pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS indexes_size_bytes
FROM pg_tables
WHERE schemaname = 'dwh'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query 3: Facts Table Size (Total)
-- Provides the total size of the facts table (including all partitions)
SELECT
    'facts_total' AS table_name,
    pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename))) AS total_size,
    SUM(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size_bytes,
    pg_size_pretty(SUM(pg_relation_size(schemaname||'.'||tablename))) AS table_size,
    SUM(pg_relation_size(schemaname||'.'||tablename)) AS table_size_bytes
FROM pg_tables
WHERE schemaname = 'dwh'
  AND (tablename = 'facts' OR tablename LIKE 'facts_%');

-- Query 4: Facts Table Size by Partition (Year)
-- Shows the size of each facts partition by year
SELECT
    tablename,
    CASE
        WHEN tablename = 'facts' THEN 'facts'
        WHEN tablename ~ '^facts_[0-9]{4}$' THEN SUBSTRING(tablename FROM 'facts_([0-9]{4})')
        ELSE 'unknown'
    END AS partition_year,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS indexes_size
FROM pg_tables
WHERE schemaname = 'dwh'
  AND (tablename = 'facts' OR tablename LIKE 'facts_%')
ORDER BY partition_year DESC NULLS LAST, tablename;

-- Query 5: Dimension Tables Size
-- Shows the size of all dimension tables
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes
FROM pg_tables
WHERE schemaname = 'dwh'
  AND tablename LIKE 'dimension_%'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query 6: Datamart Tables Size
-- Shows the size of all datamart tables
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes
FROM pg_tables
WHERE schemaname = 'dwh'
  AND tablename LIKE 'datamart%'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query 7: Index Sizes by Table
-- Shows the total size of indexes for each table
SELECT
    schemaname,
    tablename,
    pg_size_pretty(SUM(pg_relation_size(indexrelid))) AS total_indexes_size,
    SUM(pg_relation_size(indexrelid)) AS total_indexes_size_bytes,
    COUNT(*) AS index_count
FROM pg_stat_user_indexes
WHERE schemaname = 'dwh'
GROUP BY schemaname, tablename
ORDER BY SUM(pg_relation_size(indexrelid)) DESC;

-- Query 8: Largest Indexes
-- Lists the largest indexes in the dwh schema
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_relation_size(indexrelid) AS index_size_bytes,
    idx_scan AS index_scans
FROM pg_stat_user_indexes
WHERE schemaname = 'dwh'
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;

-- Query 9: Table Growth Estimation (Last 7 Days)
-- Estimates table growth based on statistics
-- Note: This requires historical data collection, simplified version shown
SELECT
    schemaname,
    tablename,
    n_live_tup AS current_row_count,
    n_dead_tup AS dead_row_count,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS current_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS current_size_bytes,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'dwh'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query 10: Database Bloat Summary
-- Provides a summary of bloat (dead tuples) across all tables
SELECT
    schemaname,
    COUNT(*) AS table_count,
    SUM(n_live_tup) AS total_live_tuples,
    SUM(n_dead_tup) AS total_dead_tuples,
    ROUND(
        SUM(n_dead_tup)::numeric / NULLIF(SUM(n_live_tup) + SUM(n_dead_tup), 0) * 100,
        2
    ) AS overall_dead_tuple_percent,
    SUM(seq_scan) AS total_sequential_scans,
    SUM(idx_scan) AS total_index_scans
FROM pg_stat_user_tables
WHERE schemaname = 'dwh'
GROUP BY schemaname;

-- Query 11: Partition Count for Facts Table
-- Counts the number of partitions for the facts table
SELECT
    COUNT(*) AS partition_count,
    COUNT(*) FILTER (WHERE tablename = 'facts') AS has_parent_table
FROM pg_tables
WHERE schemaname = 'dwh'
  AND (tablename = 'facts' OR tablename LIKE 'facts_%');

-- Query 12: Unused Indexes (Potentially)
-- Identifies indexes that are rarely or never used
-- Note: This is a heuristic - indexes might be used for constraints
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS index_scans,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_relation_size(indexrelid) AS index_size_bytes
FROM pg_stat_user_indexes
WHERE schemaname = 'dwh'
  AND idx_scan < 10
  AND pg_relation_size(indexrelid) > 1048576  -- Larger than 1MB
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;
