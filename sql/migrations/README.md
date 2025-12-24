# Database Migrations

This directory contains database migration scripts for schema changes and updates.

## Migration Script Naming Convention

Migration scripts should follow this naming pattern:
```
YYYYMMDD_HHMMSS_description.sql
```

Examples:
- `20251224_120000_add_metric_tags.sql`
- `20250125_090000_add_alert_escalation.sql`

## Migration Script Structure

Each migration script should follow this structure:

```sql
-- Migration: YYYYMMDD_HHMMSS_description
-- Description: Brief description of what this migration does
-- Author: Your Name
-- Date: YYYY-MM-DD
--
-- This migration:
-- - Does X
-- - Changes Y
-- - Adds Z

BEGIN;

-- Migration SQL here
-- Use transactions for safety

-- Example:
-- ALTER TABLE metrics ADD COLUMN tags JSONB;

-- Verify migration
-- SELECT 1; -- or other verification queries

COMMIT;
```

## Running Migrations

### Manual Migration

```bash
# Run a specific migration
psql -d osm_notes_monitoring -f sql/migrations/20251224_120000_description.sql

# Run all migrations in order
for migration in sql/migrations/*.sql; do
    psql -d osm_notes_monitoring -f "${migration}"
done
```

### Using Migration Script

```bash
# Run all pending migrations
./sql/migrations/run_migrations.sh

# Run specific migration
./sql/migrations/run_migrations.sh 20251224_120000_description.sql
```

## Migration Tracking

Migrations are tracked in the `schema_migrations` table (to be created):

```sql
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

## Best Practices

1. **Always use transactions**: Wrap migrations in BEGIN/COMMIT
2. **Make migrations reversible**: Consider creating rollback scripts
3. **Test migrations**: Test on a copy of production data first
4. **Document changes**: Include comments explaining what and why
5. **Verify after migration**: Add verification queries
6. **One change per migration**: Keep migrations focused and atomic

## Rollback Scripts

For complex migrations, create rollback scripts:
```
20251224_120000_description.sql          # Forward migration
20251224_120000_description_rollback.sql # Rollback migration
```

## Migration Order

Migrations are applied in alphabetical order (which matches chronological order with the naming convention).

## Current Schema Version

The current schema version is defined in `sql/init.sql`. After running migrations, the schema version should be updated.

## Notes

- Never modify existing migration files after they've been applied to production
- Create a new migration for any changes
- Keep migrations small and focused
- Test migrations thoroughly before applying to production

