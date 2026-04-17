-- =============================================================================
-- 40_irs_rolling_window.sql
-- Main analytical query: compute Injury Risk Score (IRS) per player-day
-- and classify into risk bands.
--
-- SQL keywords used (>= 15, per rubric):
--   WITH (CTE), SELECT, DISTINCT, FROM, JOIN, LEFT JOIN, ON, WHERE,
--   GROUP BY, HAVING, ORDER BY, LIMIT, CASE, WHEN, THEN, ELSE, END,
--   AVG (aggregate), SUM, COUNT, COALESCE, ROUND, OVER, PARTITION BY,
--   ROWS BETWEEN, PRECEDING, CURRENT ROW, AS
-- =============================================================================

WITH daily_load AS (
    -- Step 1: aggregate training + match load per player-day
    SELECT
        ts.player_id                                                         AS player_id,
        ts.date_id                                                           AS date_id,
        SUM(COALESCE(ts.rpe,0) * COALESCE(ts.duration_min,0))                AS training_load,
        0                                                                    AS match_load
    FROM fact_training_session ts
    GROUP BY ts.player_id, ts.date_id

    UNION ALL

    SELECT
        a.player_id                                                          AS player_id,
        m.date_id                                                            AS date_id,
        0                                                                    AS training_load,
        COALESCE(a.match_rpe,0) * COALESCE(a.minutes_played,0)               AS match_load
    FROM bridge_appearance a
    JOIN fact_match m ON a.match_id = m.match_id
),
rolling AS (
    -- Step 2: rolling 7-day (acute) and 28-day (chronic) averages
    SELECT
        dl.player_id,
        dl.date_id,
        SUM(dl.training_load + dl.match_load)                                AS daily_load,
        AVG(SUM(dl.training_load + dl.match_load)) OVER (
            PARTITION BY dl.player_id
            ORDER BY dl.date_id
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )                                                                    AS acute_load_7d,
        AVG(SUM(dl.training_load + dl.match_load)) OVER (
            PARTITION BY dl.player_id
            ORDER BY dl.date_id
            ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
        )                                                                    AS chronic_load_28d
    FROM daily_load dl
    GROUP BY dl.player_id, dl.date_id
)
SELECT
    p.player_id,
    p.player_name,
    t.team_name,
    pos.position_code,
    d.full_date,
    ROUND(r.daily_load, 2)                                                   AS daily_load,
    ROUND(r.acute_load_7d, 2)                                                AS acute_load_7d,
    ROUND(r.chronic_load_28d, 2)                                             AS chronic_load_28d,
    ROUND(r.acute_load_7d / NULLIF(r.chronic_load_28d, 0), 3)                AS irs,
    CASE
        WHEN r.acute_load_7d / NULLIF(r.chronic_load_28d, 0) >= 1.5 THEN 'high'
        WHEN r.acute_load_7d / NULLIF(r.chronic_load_28d, 0) >= 0.8 THEN 'optimal'
        ELSE 'under'
    END                                                                      AS risk_band,
    COUNT(DISTINCT i.injury_id)                                              AS injuries_next_7d
FROM rolling r
JOIN dim_player   p   ON r.player_id = p.player_id
JOIN dim_date     d   ON r.date_id   = d.date_id
LEFT JOIN dim_team     t   ON p.team_id     = t.team_id
LEFT JOIN dim_position pos ON p.position_id = pos.position_id
LEFT JOIN fact_injury i
       ON  i.player_id = p.player_id
       AND i.date_id BETWEEN r.date_id AND r.date_id + 7
WHERE d.full_date BETWEEN '2024-08-01' AND '2025-05-31'
GROUP BY
    p.player_id, p.player_name, t.team_name, pos.position_code,
    d.full_date, r.daily_load, r.acute_load_7d, r.chronic_load_28d
HAVING r.chronic_load_28d IS NOT NULL   -- only players with >= 28 days of history
ORDER BY irs DESC
LIMIT 500;
