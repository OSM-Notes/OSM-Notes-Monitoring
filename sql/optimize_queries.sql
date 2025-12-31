-- Query Performance Optimization Script
-- Version: 1.0.0
-- Date: 2025-12-31
--
-- This script creates additional indexes and optimizations for frequently executed queries
-- Run this script after initial schema setup to improve query performance
--
-- Usage:
--   psql -d osm_notes_monitoring -f sql/optimize_queries.sql

-- ============================================================================
-- Additional Indexes for Query Optimization
-- ============================================================================

-- Index for filtering metrics by component and metric_name with time range
-- Used by: get_latest_metric_value, aggregate_metrics
CREATE INDEX IF NOT EXISTS idx_metrics_component_metric_name_timestamp 
    ON metrics(component, metric_name, timestamp DESC);

-- Partial index for active alerts (most common query)
-- Used by: get_active_alerts, alert deduplication
CREATE INDEX IF NOT EXISTS idx_alerts_active_status_created 
    ON alerts(status, created_at DESC) 
    WHERE status = 'active';

-- Index for alert deduplication queries
-- Used by: check_duplicate_alert
CREATE INDEX IF NOT EXISTS idx_alerts_component_type_level_created 
    ON alerts(component, alert_type, alert_level, created_at DESC);

-- Index for component health lookups (already exists but ensure it's optimal)
-- Used by: get_component_health
-- Note: component_health table has PRIMARY KEY on component, so this is already optimized

-- Note: Security event indexes already exist in init.sql
-- idx_security_events_ip_timestamp - already exists
-- idx_security_events_type_timestamp - already exists

-- Composite index for IP management lookups
-- Used by: check_ip_whitelist, check_ip_blacklist
-- Note: Filter by expires_at in queries (NULL or future = active)
CREATE INDEX IF NOT EXISTS idx_ip_management_ip_type_expires 
    ON ip_management(ip_address, list_type, expires_at);

-- ============================================================================
-- Statistics Update
-- ============================================================================

-- Update table statistics for better query planning
ANALYZE metrics;
ANALYZE alerts;
ANALYZE component_health;
ANALYZE security_events;
ANALYZE ip_management;

-- ============================================================================
-- Query Plan Analysis
-- ============================================================================

-- Enable query plan analysis (for PostgreSQL 12+)
-- This helps identify slow queries
-- Note: Requires pg_stat_statements extension
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- ============================================================================
-- Vacuum Configuration Recommendations
-- ============================================================================

-- For high-write tables, consider more frequent VACUUM
-- Run periodically: VACUUM ANALYZE metrics;
-- Run periodically: VACUUM ANALYZE alerts;
-- Run periodically: VACUUM ANALYZE security_events;

-- ============================================================================
-- Performance Monitoring Queries
-- ============================================================================

-- Query 1: Check index usage
-- Identifies unused indexes that could be dropped
-- Note: These are example queries for monitoring, not executed automatically
-- SELECT 
--     schemaname,
--     tablename,
--     indexname,
--     idx_scan AS index_scans,
--     pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
-- FROM pg_stat_user_indexes
-- WHERE schemaname = 'public'
--   AND idx_scan = 0
-- ORDER BY pg_relation_size(indexrelid) DESC;

-- Query 2: Check table bloat
-- Identifies tables that need VACUUM
-- SELECT 
--     schemaname,
--     relname AS tablename,
--     n_live_tup AS live_tuples,
--     n_dead_tup AS dead_tuples,
--     ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_percent,
--     last_vacuum,
--     last_autovacuum
-- FROM pg_stat_user_tables
-- WHERE schemaname = 'public'
--   AND n_dead_tup > 1000
-- ORDER BY n_dead_tup DESC;

-- Query 3: Check sequential scans
-- Identifies tables that might benefit from additional indexes
-- SELECT 
--     schemaname,
--     relname AS tablename,
--     seq_scan AS sequential_scans,
--     idx_scan AS index_scans,
--     ROUND(seq_scan * 100.0 / NULLIF(seq_scan + idx_scan, 0), 2) AS seq_scan_percent,
--     n_live_tup AS live_tuples
-- FROM pg_stat_user_tables
-- WHERE schemaname = 'public'
--   AND seq_scan > 100
-- ORDER BY seq_scan DESC;

-- Query 4: Index sizes
-- Shows index sizes to identify large indexes
-- SELECT 
--     schemaname,
--     tablename,
--     indexname,
--     pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
--     pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
--     ROUND(pg_relation_size(indexrelid) * 100.0 / NULLIF(pg_relation_size(schemaname||'.'||tablename), 0), 2) AS index_to_table_ratio
-- FROM pg_stat_user_indexes
-- WHERE schemaname = 'public'
-- ORDER BY pg_relation_size(indexrelid) DESC;
