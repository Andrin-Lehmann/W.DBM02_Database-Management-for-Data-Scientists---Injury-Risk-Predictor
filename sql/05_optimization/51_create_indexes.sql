-- 51_create_indexes.sql
-- Indexes are already defined inline in the DDL (01_create_tables.sql).
-- This script re-asserts them for traceability and adds one covering index
-- for dashboard risk-band filtering. MySQL will warn if an index already exists.

USE injury_risk_predictor;

-- composite: window function partitions on mm_athlete_id, orders by date_id
CREATE INDEX IF NOT EXISTS idx_ts_athlete_date
    ON fact_training_session (mm_athlete_id, date_id);

-- composite: injury lookups by bridge + date
CREATE INDEX IF NOT EXISTS idx_inj_bridge_date
    ON fact_injury_european (bridge_id, date_id);

-- bridge lookups by team
CREATE INDEX IF NOT EXISTS idx_bpt_team
    ON bridge_player_team (team_id);

-- covering index: Metabase dashboard filters on risk_band + date range
CREATE INDEX IF NOT EXISTS idx_lm_band_date
    ON fact_load_metrics (risk_band, date_id);

ANALYZE TABLE fact_training_session, fact_injury_european, bridge_player_team, fact_load_metrics;
