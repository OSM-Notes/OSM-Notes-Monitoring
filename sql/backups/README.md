# Database Backup and Restore

This directory contains scripts for backing up and restoring the OSM-Notes-Monitoring database.

## Scripts

### `backup_database.sh`

Creates a backup of the monitoring database.

**Usage:**

```bash
# Basic backup
./sql/backups/backup_database.sh

# Backup with compression
./sql/backups/backup_database.sh -c

# Backup to specific directory
./sql/backups/backup_database.sh -o /path/to/backups

# Backup with retention policy (keep 7 days)
./sql/backups/backup_database.sh -r 7

# List existing backups
./sql/backups/backup_database.sh -l
```

**Options:**

- `-d, --database DATABASE`: Database name (default: osm_notes_monitoring)
- `-o, --output DIR`: Output directory (default: sql/backups)
- `-r, --retention DAYS`: Keep backups for N days (default: 30)
- `-c, --compress`: Compress backup with gzip
- `-v, --verbose`: Verbose output
- `-l, --list`: List existing backups

**Backup Format:**

- Filename: `{database}_{YYYYMMDD_HHMMSS}.sql` or `.sql.gz`
- Format: Plain SQL (pg_dump format)
- Includes: Schema and data

### `restore_database.sh`

Restores a backup to the database.

**Usage:**

```bash
# Restore from backup
./sql/backups/restore_database.sh backup.sql

# Restore compressed backup
./sql/backups/restore_database.sh backup.sql.gz

# Force restore (drop existing database)
./sql/backups/restore_database.sh -f backup.sql

# Restore to different database
./sql/backups/restore_database.sh -d test_db backup.sql
```

**Options:**

- `-d, --database DATABASE`: Target database name (default: osm_notes_monitoring)
- `-f, --force`: Force restore (drop existing database)
- `-v, --verbose`: Verbose output

**WARNING:** This will overwrite the target database!

## Backup Strategy

### Recommended Schedule

- **Daily backups**: Full backup every day
- **Retention**: Keep backups for 30 days (configurable)
- **Compression**: Use compression for space savings
- **Off-site**: Copy backups to remote location

### Example Cron Job

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/OSM-Notes-Monitoring/sql/backups/backup_database.sh -c -r 30
```

### Backup Before Migrations

Always backup before running migrations:

```bash
# 1. Create backup
./sql/backups/backup_database.sh -c

# 2. Run migrations
./sql/migrations/run_migrations.sh

# 3. If something goes wrong, restore
./sql/backups/restore_database.sh -f backup.sql.gz
```

## Backup File Format

Backups are created using `pg_dump` in plain SQL format:

- **Uncompressed**: `.sql` files (readable text)
- **Compressed**: `.sql.gz` files (gzip compressed)

Both formats can be restored using `restore_database.sh`.

## Restore Process

The restore process:

1. Checks if backup file exists
2. Optionally drops existing database (with `-f` flag)
3. Creates new database
4. Restores schema and data from backup
5. Verifies restore completed successfully

## Best Practices

1. **Regular Backups**: Schedule daily backups
2. **Test Restores**: Periodically test restore process
3. **Off-site Storage**: Copy backups to remote location
4. **Before Migrations**: Always backup before schema changes
5. **Retention Policy**: Keep backups according to your needs
6. **Compression**: Use compression to save space
7. **Verification**: Verify backup files are not corrupted

## Troubleshooting

### Backup Fails

- Check PostgreSQL connection
- Verify database exists
- Check disk space
- Verify write permissions on backup directory

### Restore Fails

- Check backup file is not corrupted
- Verify PostgreSQL connection
- Check disk space
- Ensure database doesn't exist (or use `-f` flag)

### Large Backup Files

- Use compression (`-c` flag)
- Consider excluding large tables if not needed
- Archive old backups to external storage

## Examples

### Full Backup Workflow

```bash
# 1. Create backup
./sql/backups/backup_database.sh -c -o /backups

# 2. List backups
./sql/backups/backup_database.sh -l

# 3. Restore if needed
./sql/backups/restore_database.sh -f /backups/osm_notes_monitoring_20251224_020000.sql.gz
```

### Test Database Restore

```bash
# Backup production
./sql/backups/backup_database.sh -d osm_notes_monitoring -c

# Restore to test database
./sql/backups/restore_database.sh -d osm_notes_monitoring_test -f osm_notes_monitoring_*.sql.gz
```
