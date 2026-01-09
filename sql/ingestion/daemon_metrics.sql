-- Daemon Metrics Queries
-- Queries to support daemon monitoring metrics collection
-- Version: 1.0.0
-- Date: 2026-01-08

-- Get last processed timestamp from notes table
-- This helps determine the freshness of data processed by the daemon
SELECT 
    MAX(created_at) as last_note_timestamp,
    MAX(updated_at) as last_update_timestamp,
    COUNT(*) as total_notes
FROM notes;

-- Get notes processed in last hour
-- Used to calculate processing rate
SELECT 
    COUNT(*) as notes_processed_last_hour,
    COUNT(DISTINCT id) as unique_notes,
    MIN(created_at) as oldest_note,
    MAX(created_at) as newest_note
FROM notes
WHERE created_at > NOW() - INTERVAL '1 hour';

-- Get notes processed in last cycle (assuming cycles are ~1 minute)
-- This helps track per-cycle processing
SELECT 
    COUNT(*) as notes_in_last_minute,
    COUNT(CASE WHEN created_at > NOW() - INTERVAL '1 minute' THEN 1 END) as new_notes,
    COUNT(CASE WHEN updated_at > NOW() - INTERVAL '1 minute' AND created_at < NOW() - INTERVAL '1 minute' THEN 1 END) as updated_notes
FROM notes
WHERE created_at > NOW() - INTERVAL '1 minute' 
   OR updated_at > NOW() - INTERVAL '1 minute';

-- Get comments processed in last hour
SELECT 
    COUNT(*) as comments_processed_last_hour,
    COUNT(DISTINCT note_id) as notes_with_comments,
    MIN(created_at) as oldest_comment,
    MAX(created_at) as newest_comment
FROM note_comments
WHERE created_at > NOW() - INTERVAL '1 hour';

-- Get comments processed in last cycle
SELECT 
    COUNT(*) as comments_in_last_minute
FROM note_comments
WHERE created_at > NOW() - INTERVAL '1 minute';

-- Get processing statistics for last N cycles (if we had a processing_log table)
-- This is a placeholder query for when processing_log table is created
-- Currently, we rely on log parsing for cycle information
/*
CREATE TABLE IF NOT EXISTS processing_log (
    id SERIAL PRIMARY KEY,
    cycle_number INTEGER NOT NULL,
    cycle_start_time TIMESTAMP NOT NULL,
    cycle_end_time TIMESTAMP,
    cycle_duration_seconds INTEGER,
    notes_processed INTEGER DEFAULT 0,
    notes_new INTEGER DEFAULT 0,
    notes_updated INTEGER DEFAULT 0,
    comments_processed INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'success',
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_processing_log_cycle_number ON processing_log(cycle_number);
CREATE INDEX IF NOT EXISTS idx_processing_log_cycle_start_time ON processing_log(cycle_start_time);
CREATE INDEX IF NOT EXISTS idx_processing_log_status ON processing_log(status);

-- Query to get last N cycles statistics
SELECT 
    cycle_number,
    cycle_start_time,
    cycle_end_time,
    cycle_duration_seconds,
    notes_processed,
    notes_new,
    notes_updated,
    comments_processed,
    status
FROM processing_log
ORDER BY cycle_number DESC
LIMIT 10;

-- Query to calculate cycle success rate
SELECT 
    COUNT(*) as total_cycles,
    COUNT(CASE WHEN status = 'success' THEN 1 END) as successful_cycles,
    COUNT(CASE WHEN status != 'success' THEN 1 END) as failed_cycles,
    ROUND(COUNT(CASE WHEN status = 'success' THEN 1 END) * 100.0 / COUNT(*), 2) as success_rate_percent,
    AVG(cycle_duration_seconds) as avg_duration_seconds,
    MIN(cycle_duration_seconds) as min_duration_seconds,
    MAX(cycle_duration_seconds) as max_duration_seconds
FROM processing_log
WHERE cycle_start_time > NOW() - INTERVAL '24 hours';

-- Query to get cycles per hour
SELECT 
    DATE_TRUNC('hour', cycle_start_time) as hour,
    COUNT(*) as cycles_per_hour,
    AVG(cycle_duration_seconds) as avg_duration_seconds
FROM processing_log
WHERE cycle_start_time > NOW() - INTERVAL '24 hours'
GROUP BY DATE_TRUNC('hour', cycle_start_time)
ORDER BY hour DESC;
*/

-- Get gap between last note in database and current time
-- This helps detect if processing has stopped
SELECT 
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) as gap_seconds,
    MAX(created_at) as last_note_timestamp,
    NOW() as current_timestamp
FROM notes;

-- Get processing rate statistics (notes per second) from recent activity
-- This calculates based on notes created in last hour
SELECT 
    COUNT(*) as notes_last_hour,
    EXTRACT(EPOCH FROM (NOW() - MIN(created_at))) as time_span_seconds,
    CASE 
        WHEN EXTRACT(EPOCH FROM (NOW() - MIN(created_at))) > 0 
        THEN ROUND(COUNT(*)::numeric / EXTRACT(EPOCH FROM (NOW() - MIN(created_at))), 2)
        ELSE 0
    END as notes_per_second
FROM notes
WHERE created_at > NOW() - INTERVAL '1 hour';
