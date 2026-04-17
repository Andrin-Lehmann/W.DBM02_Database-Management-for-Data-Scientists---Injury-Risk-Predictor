-- =============================================================================
-- 51_create_indexes.sql
-- Indexing strategy for the IRS query.
-- Expected effect: replaces full scans of fact_training_session and
-- bridge_appearance with range scans on the composite (player_id, date_id) key.
-- =============================================================================

-- Already present inline in the DDL, but re-asserted here for traceability.
-- If running after 01_create_tables.sql, MySQL will warn that the keys exist.

CREATE INDEX IF NOT EXISTS idx_session_player_date
    ON fact_training_session (player_id, date_id);

CREATE INDEX IF NOT EXISTS idx_injury_player_date
    ON fact_injury (player_id, date_id);

CREATE INDEX IF NOT EXISTS idx_appearance_player
    ON bridge_appearance (player_id);

-- Covering index on the materialized load table — supports dashboard filters
CREATE INDEX IF NOT EXISTS idx_load_band_date
    ON fact_load_metrics (risk_band, date_id);

ANALYZE TABLE fact_training_session, fact_injury, bridge_appearance, fact_load_metrics;
