-- =============================================================================
-- 52_materialized_irs.sql
-- MySQL 8 has no native materialized views. We emulate with a summary table
-- that is truncated and reloaded by INSERT ... SELECT. In production this
-- would be scheduled nightly via EVENT or an external scheduler.
--
-- The SELECT block is the same CTE pipeline as 40_irs_rolling_window.sql
-- but without the dashboard-facing LIMIT/ORDER BY so it stays a
-- canonical player-day table.
-- =============================================================================

TRUNCATE TABLE fact_load_metrics;

INSERT INTO fact_load_metrics
    (player_id, date_id, daily_load, acute_load_7d, chronic_load_28d, irs, risk_band)
WITH daily_load AS (
    SELECT ts.player_id, ts.date_id,
           SUM(COALESCE(ts.rpe,0) * COALESCE(ts.duration_min,0)) AS load_val
    FROM fact_training_session ts
    GROUP BY ts.player_id, ts.date_id
    UNION ALL
    SELECT a.player_id, m.date_id,
           COALESCE(a.match_rpe,0) * COALESCE(a.minutes_played,0) AS load_val
    FROM bridge_appearance a
    JOIN fact_match m ON a.match_id = m.match_id
),
rolling AS (
    SELECT
        player_id,
        date_id,
        SUM(load_val) AS daily_load,
        AVG(SUM(load_val)) OVER (
            PARTITION BY player_id ORDER BY date_id
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS acute_load_7d,
        AVG(SUM(load_val)) OVER (
            PARTITION BY player_id ORDER BY date_id
            ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
        ) AS chronic_load_28d
    FROM daily_load
    GROUP BY player_id, date_id
)
SELECT
    player_id,
    date_id,
    ROUND(daily_load, 2),
    ROUND(acute_load_7d, 2),
    ROUND(chronic_load_28d, 2),
    ROUND(acute_load_7d / NULLIF(chronic_load_28d, 0), 3) AS irs,
    CASE
        WHEN acute_load_7d / NULLIF(chronic_load_28d, 0) >= 1.5 THEN 'high'
        WHEN acute_load_7d / NULLIF(chronic_load_28d, 0) >= 0.8 THEN 'optimal'
        ELSE 'under'
    END AS risk_band
FROM rolling
WHERE chronic_load_28d IS NOT NULL;
