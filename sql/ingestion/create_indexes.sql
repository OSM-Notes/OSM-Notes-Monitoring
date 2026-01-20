-- Create Recommended Indexes for Ingestion Monitoring Queries
-- Version: 1.0.0
-- Date: 2025-12-24
--
-- This script creates indexes to optimize query performance
-- Run this script after initial schema setup
-- See optimization_recommendations.md for details

-- Notes table indexes
CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_note_id ON notes(note_id);
CREATE INDEX IF NOT EXISTS idx_notes_coordinates ON notes(latitude, longitude);

-- Partial index for recent updates (optimizes freshness queries)
CREATE INDEX IF NOT EXISTS idx_notes_recent_updates
ON notes(updated_at DESC)
WHERE updated_at > NOW() - INTERVAL '30 days';

-- Note comments table indexes
CREATE INDEX IF NOT EXISTS idx_note_comments_note_id ON note_comments(note_id);
CREATE INDEX IF NOT EXISTS idx_note_comments_created_at ON note_comments(
    created_at DESC
);
CREATE INDEX IF NOT EXISTS idx_note_comments_note_id_created_at ON note_comments(
    note_id, created_at DESC
);

-- Note comment texts table indexes
CREATE INDEX IF NOT EXISTS idx_note_comment_texts_comment_id ON note_comment_texts(
    comment_id
);

-- Processing log table indexes (if table exists)
-- Note: These will fail silently if table doesn't exist
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'processing_log') THEN
        CREATE INDEX IF NOT EXISTS idx_processing_log_execution_time ON processing_log(execution_time DESC);
        CREATE INDEX IF NOT EXISTS idx_processing_log_status ON processing_log(status);
        CREATE INDEX IF NOT EXISTS idx_processing_log_status_execution_time ON processing_log(status, execution_time DESC);
        
        -- Covering index for common queries
        CREATE INDEX IF NOT EXISTS idx_processing_log_covering 
        ON processing_log(status, execution_time DESC, duration_seconds, notes_processed);
    END IF;
END $$;

-- Hash index for duplicate detection (if needed)
CREATE INDEX IF NOT EXISTS idx_notes_note_id_hash ON notes USING HASH(note_id);

-- Partial index for quality checks
CREATE INDEX IF NOT EXISTS idx_notes_quality_check
ON notes(id)
WHERE latitude IS NULL OR longitude IS NULL OR updated_at < created_at;

-- Analyze tables after creating indexes
ANALYZE notes;
ANALYZE note_comments;
ANALYZE note_comment_texts;

-- Analyze processing_log if it exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'processing_log') THEN
        ANALYZE processing_log;
    END IF;
END $$;
