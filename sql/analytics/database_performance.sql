-- Database Performance Metrics for Analytics Monitoring
-- Version: 1.0.0
-- Date: 2026-01-09
--
-- These queries retrieve database performance metrics from PostgreSQL
-- for the Analytics data warehouse (schema 'dwh').

-- Query 1: Cache Hit Ratio
-- Provides the overall cache hit ratio for the database
SELECT ROUND(
        SUM(
            heap_blks_hit
        )::numeric / NULLIF(SUM(heap_blks_hit) + SUM(heap_blks_read), 0) * 100,
        2
    ) AS cache_hit_ratio_percent
FROM pg_statio_user_tables
WHERE schemaname = 'dwh';

-- Query 2: Slow Queries (Top 10)
-- Identifies the slowest queries currently running or recently executed
SELECT
    pid,
    usename,
    application_name,
    state,
    query_start,
    state_change,
    wait_event_type,
    wait_event,
    EXTRACT(EPOCH FROM (NOW() - query_start))::bigint AS query_duration_seconds,
    LEFT(query, 100) AS query_preview
FROM pg_stat_activity
WHERE datname = CURRENT_DATABASE()
      AND state != 'idle'
      AND query_start < NOW() - interval '1 second'
ORDER BY query_start ASC
LIMIT 10;

-- Query 3: Active Connections by Application
-- Shows the number of active connections grouped by application name
SELECT
    application_name,
    COUNT(*) AS active_connections,
    COUNT(*) FILTER (WHERE state = 'active') AS active_queries,
    COUNT(*) FILTER (WHERE state = 'idle') AS idle_connections,
    COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction
FROM pg_stat_activity
WHERE datname = CURRENT_DATABASE()
GROUP BY application_name
ORDER BY active_connections DESC;

-- Query 4: Active Locks
-- Lists all active locks in the database
SELECT
    locktype,
    database,
    relation::regclass AS table_name,
    mode,
    granted,
    COUNT(*) AS lock_count
FROM pg_locks
WHERE
    database = (SELECT oid FROM pg_database WHERE datname = CURRENT_DATABASE())
GROUP BY locktype, database, relation, mode, granted
ORDER BY lock_count DESC;

-- Query 5: Blocking Queries
-- Identifies queries that are blocking other queries
SELECT
    pg_catalog.pg_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS blocking_statement,
    blocked_activity.application_name AS blocked_application,
    blocking_activity.application_name AS blocking_application
FROM pg_catalog.pg_locks
    INNER JOIN
        pg_catalog.pg_stat_activity AS blocked_activity ON
            blocked_activity.pid = pg_catalog.pg_locks.pid
    INNER JOIN
        pg_catalog.pg_locks AS blocking_locks ON
            blocking_locks.locktype = pg_catalog.pg_locks.locktype
            AND blocking_locks.database IS NOT DISTINCT FROM pg_catalog.pg_locks.database
            AND blocking_locks.relation IS NOT DISTINCT FROM pg_catalog.pg_locks.relation
            AND blocking_locks.page IS NOT DISTINCT FROM pg_catalog.pg_locks.page
            AND blocking_locks.tuple IS NOT DISTINCT FROM pg_catalog.pg_locks.tuple
            AND blocking_locks.virtualxid IS NOT DISTINCT FROM pg_catalog.pg_locks.virtualxid
            AND blocking_locks.transactionid IS NOT DISTINCT FROM pg_catalog.pg_locks.transactionid
            AND blocking_locks.classid IS NOT DISTINCT FROM pg_catalog.pg_locks.classid
            AND blocking_locks.objid IS NOT DISTINCT FROM pg_catalog.pg_locks.objid
            AND blocking_locks.objsubid IS NOT DISTINCT FROM pg_catalog.pg_locks.objsubid
            AND blocking_locks.pid != pg_catalog.pg_locks.pid
    INNER JOIN
        pg_catalog.pg_stat_activity AS blocking_activity ON
            blocking_activity.pid = blocking_locks.pid
WHERE NOT pg_catalog.pg_locks.granted;

-- Query 6: Table Bloat Estimation
-- Estimates bloat (wasted space) for tables in the dwh schema
-- Note: This requires the pgstattuple extension for accurate results
-- This is a simplified version using pg_stat_user_tables
SELECT
    schemaname,
    tablename,
    n_dead_tup AS dead_tuples,
    n_live_tup AS live_tuples,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    CASE
        WHEN
            n_live_tup > 0 THEN ROUND(
                (n_dead_tup::numeric / n_live_tup) * 100, 2
            )
        ELSE 0
    END AS dead_tuple_percent
FROM pg_stat_user_tables
WHERE schemaname = 'dwh'
ORDER BY n_dead_tup DESC
LIMIT 20;

-- Query 7: Index Usage Statistics
-- Shows index usage statistics for tables in the dwh schema
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    PG_SIZE_PRETTY(PG_RELATION_SIZE(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'dwh'
ORDER BY idx_scan ASC, PG_RELATION_SIZE(indexrelid) DESC
LIMIT 20;

-- Query 8: Table Statistics Summary
-- Provides summary statistics for all tables in the dwh schema
SELECT
    schemaname,
    tablename,
    n_live_tup AS row_count,
    n_dead_tup AS dead_rows,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    seq_scan AS sequential_scans,
    seq_tup_read AS sequential_tuples_read,
    idx_scan AS index_scans,
    idx_tup_fetch AS index_tuples_fetched,
    PG_SIZE_PRETTY(
        PG_TOTAL_RELATION_SIZE(schemaname || '.' || tablename)
    ) AS total_size,
    PG_SIZE_PRETTY(
        PG_RELATION_SIZE(schemaname || '.' || tablename)
    ) AS table_size,
    PG_SIZE_PRETTY(
        PG_TOTAL_RELATION_SIZE(
            schemaname || '.' || tablename
        ) - PG_RELATION_SIZE(schemaname || '.' || tablename)
    ) AS indexes_size
FROM pg_stat_user_tables
WHERE schemaname = 'dwh'
ORDER BY PG_TOTAL_RELATION_SIZE(schemaname || '.' || tablename) DESC;

-- Query 9: Connection Pool Status
-- Shows current connection pool status
SELECT
    COUNT(*) AS total_connections,
    COUNT(*) FILTER (WHERE state = 'active') AS active_connections,
    COUNT(*) FILTER (WHERE state = 'idle') AS idle_connections,
    COUNT(
        *
    ) FILTER (
        WHERE state = 'idle in transaction'
    ) AS idle_in_transaction_connections,
    (
        SELECT setting::integer FROM pg_settings WHERE name = 'max_connections'
    ) AS max_connections,
    ROUND(
        COUNT(
            *
        )::numeric / NULLIF(
            (
                SELECT setting::integer
                FROM pg_settings WHERE name = 'max_connections'
            ),
            0
        ) * 100,
        2
    ) AS connection_usage_percent
FROM pg_stat_activity
WHERE datname = CURRENT_DATABASE();

-- Query 10: Long Running Queries
-- Identifies queries that have been running for more than a specified duration
SELECT
    pid,
    usename,
    application_name,
    state,
    query_start,
    EXTRACT(EPOCH FROM (NOW() - query_start))::bigint AS duration_seconds,
    LEFT(query, 200) AS query_preview
FROM pg_stat_activity
WHERE datname = CURRENT_DATABASE()
      AND state = 'active'
      AND query_start < NOW() - interval '30 seconds'
ORDER BY query_start ASC;

-- Query 11: Database Size
-- Shows the total size of the current database
SELECT
    PG_SIZE_PRETTY(PG_DATABASE_SIZE(CURRENT_DATABASE())) AS database_size,
    PG_DATABASE_SIZE(CURRENT_DATABASE()) AS database_size_bytes;

-- Query 12: WAL Statistics (if available)
-- Shows Write-Ahead Log statistics
SELECT
    PG_SIZE_PRETTY(PG_CURRENT_WAL_LSN() - '0/0'::pg_lsn) AS wal_size,
    PG_SIZE_PRETTY(PG_WAL_LSN_DIFF(PG_CURRENT_WAL_LSN(), PG_LAST_WAL_REPLAY_LSN())) AS replication_lag;
