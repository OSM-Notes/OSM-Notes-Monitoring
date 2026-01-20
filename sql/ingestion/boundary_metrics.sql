-- Boundary Processing Metrics Queries
-- Queries for monitoring country and maritime boundary processing

-- Query 1: Get last update timestamps for boundaries
-- Returns: Countries last update, maritime boundaries last update
SELECT
    (
        SELECT MAX(updated_at)
        FROM countries
        WHERE updated_at IS NOT NULL
    ) AS countries_last_update,
    (
        SELECT MAX(updated_at)
        FROM maritime_boundaries
        WHERE updated_at IS NOT NULL
    ) AS maritime_boundaries_last_update;

-- Query 2: Calculate update frequency (hours since last update)
-- Returns: Hours since last update for countries and maritime boundaries
SELECT
    (
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) / 3600
        FROM countries
        WHERE updated_at IS NOT NULL
    )::integer AS countries_update_age_hours,
    (
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) / 3600
        FROM maritime_boundaries
        WHERE updated_at IS NOT NULL
    )::integer AS maritime_update_age_hours;

-- Query 3: Count notes without country assignment
-- Returns: Total notes, notes without country, notes with country, percentage without country
SELECT
    COUNT(*) AS total_notes,
    COUNT(*) FILTER (WHERE country_id IS NULL) AS notes_without_country,
    COUNT(*) FILTER (WHERE country_id IS NOT NULL) AS notes_with_country,
    ROUND(
        COUNT(
            *
        ) FILTER (WHERE country_id IS NULL) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS percentage_without_country
FROM notes;

-- Query 4: Notes with invalid coordinates (out of bounds)
-- Returns: Count of notes with coordinates outside valid ranges
SELECT COUNT(*) AS notes_out_of_bounds
FROM notes
WHERE latitude < -90 OR latitude > 90
      OR longitude < -180 OR longitude > 180;

-- Query 5: Notes with country_id that doesn't exist in countries table
-- Returns: Count of notes with invalid country_id references
SELECT COUNT(*) AS notes_wrong_country
FROM notes AS n
WHERE n.country_id IS NOT NULL
      AND NOT EXISTS (
      SELECT 1 FROM countries AS c WHERE c.id = n.country_id
      );

-- Query 5a: Notes with spatial mismatch (coordinates outside assigned country)
-- This detects notes that need reassignment after boundary updates
-- Returns: Count of notes geographically outside their assigned country
-- Note: This query uses PostGIS if available, otherwise uses bounding box check
SELECT COUNT(*) AS notes_spatial_mismatch
FROM notes AS n
WHERE n.country_id IS NOT NULL
      AND n.latitude IS NOT NULL
      AND n.longitude IS NOT NULL
      AND EXISTS (
      SELECT 1 FROM countries AS c
      WHERE c.id = n.country_id
        AND (
            -- Bounding box check (fallback if PostGIS not available)
            n.latitude < COALESCE(c.min_latitude, -90)
            OR n.latitude > COALESCE(c.max_latitude, 90)
            OR n.longitude < COALESCE(c.min_longitude, -180)
            OR n.longitude > COALESCE(c.max_longitude, 180)
            -- PostGIS spatial check (if geometry column exists)
            OR (
                c.geometry IS NOT NULL
                AND NOT ST_CONTAINS(
                    c.geometry,
                    ST_SETSRID(ST_MAKEPOINT(n.longitude, n.latitude), 4326)
                )
            )
        )
      );

-- Query 5b: Notes affected by boundary changes
-- Returns: Count of notes that were assigned before last boundary update
-- and might need reassignment
SELECT COUNT(*) AS notes_affected_by_changes
FROM notes AS n
WHERE n.country_id IS NOT NULL
      AND n.latitude IS NOT NULL
      AND n.longitude IS NOT NULL
      AND n.updated_at < (
      SELECT MAX(updated_at) FROM countries WHERE updated_at IS NOT NULL
      )
      AND EXISTS (
      SELECT 1 FROM countries AS c
      WHERE c.id = n.country_id
        AND c.updated_at > n.updated_at
      );

-- Query 6: Country assignment statistics by country
-- Returns: Country name, total notes, percentage of all notes
SELECT
    c.name AS country_name,
    COUNT(n.id) AS notes_count,
    ROUND(
        COUNT(n.id) * 100.0 / NULLIF((SELECT COUNT(*) FROM notes), 0), 2
    ) AS percentage_of_total
FROM countries AS c
    LEFT JOIN notes AS n ON n.country_id = c.id
GROUP BY c.id, c.name
ORDER BY notes_count DESC
LIMIT 20;

-- Query 7: Notes without country by creation date (trend)
-- Returns: Date, total notes created, notes without country, percentage without country
SELECT
    DATE(created_at) AS date,
    COUNT(*) AS total_notes_created,
    COUNT(*) FILTER (WHERE country_id IS NULL) AS notes_without_country,
    ROUND(
        COUNT(
            *
        ) FILTER (WHERE country_id IS NULL) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS percentage_without_country
FROM notes
WHERE created_at > NOW() - interval '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Query 8: Boundary update history (if updated_at tracking exists)
-- Returns: Update date, type (countries/maritime), number of records updated
SELECT
    DATE(updated_at) AS update_date,
    'countries' AS boundary_type,
    COUNT(*) AS records_count
FROM countries
WHERE updated_at IS NOT NULL
      AND updated_at > NOW() - interval '90 days'
GROUP BY DATE(updated_at)

UNION ALL

SELECT
    DATE(updated_at) AS update_date,
    'maritime_boundaries' AS boundary_type,
    COUNT(*) AS records_count
FROM maritime_boundaries
WHERE updated_at IS NOT NULL
      AND updated_at > NOW() - interval '90 days'
GROUP BY DATE(updated_at)

ORDER BY update_date DESC;

-- Query 9: Notes with coordinates near country boundaries (potential misassignments)
-- This is a simplified check - full implementation would require PostGIS spatial queries
-- Returns: Notes that might be misassigned (simplified check)
SELECT
    n.id AS note_id,
    n.latitude,
    n.longitude,
    c.name AS assigned_country,
    COUNT(*) AS potential_issues
FROM notes AS n
    INNER JOIN countries AS c ON c.id = n.country_id
WHERE n.latitude IS NOT NULL
      AND n.longitude IS NOT NULL
GROUP BY n.id, n.latitude, n.longitude, c.name
-- Simplified: notes that appear multiple times (potential duplicates)
HAVING COUNT(*) > 1
LIMIT 100;

-- Query 10: Summary of boundary processing health
-- Returns: Overall health metrics
SELECT
    (
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) / 3600
        FROM countries
        WHERE updated_at IS NOT NULL
    )::integer AS countries_update_age_hours,
    (
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) / 3600
        FROM maritime_boundaries
        WHERE updated_at IS NOT NULL
    )::integer AS maritime_update_age_hours,
    (
        SELECT COUNT(*) FROM notes WHERE country_id IS NULL
    ) AS notes_without_country,
    (
        SELECT COUNT(*) FROM notes WHERE country_id IS NOT NULL
    ) AS notes_with_country,
    (
        SELECT COUNT(*) FROM notes
        WHERE latitude < -90 OR latitude > 90
              OR longitude < -180 OR longitude > 180
    ) AS notes_out_of_bounds,
    (
        SELECT COUNT(*) FROM notes AS n
        WHERE n.country_id IS NOT NULL
              AND NOT EXISTS (
              SELECT 1 FROM countries AS c WHERE c.id = n.country_id
              )
    ) AS notes_wrong_country;
