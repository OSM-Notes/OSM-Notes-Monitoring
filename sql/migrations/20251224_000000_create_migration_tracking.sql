-- Migration: 20251224_000000_create_migration_tracking
-- Description: Create schema_migrations table for tracking applied migrations
-- Author: System
-- Date: 2025-12-24
--
-- This migration creates the schema_migrations table that tracks
-- which migrations have been applied to the database.

BEGIN;

-- Create migration tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);

-- Add comment
COMMENT ON TABLE schema_migrations IS 'Tracks which database migrations have been applied';

-- Verify migration
SELECT 1 FROM schema_migrations LIMIT 1;

COMMIT;

