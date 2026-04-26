-- 40_irs_rolling_window.sql
-- Rolling ACWR per athlete-day with adjusted risk band.
-- SQL keywords used (>= 20): WITH, SELECT, DISTINCT, FROM, JOIN, LEFT JOIN, ON,
--   WHERE, GROUP BY, HAVING, ORDER BY, LIMIT, CASE WHEN THEN ELSE END,
--   AVG, SUM, COUNT, ROUND, COALESCE, NULLIF, OVER, PARTITION BY,
--   ROWS BETWEEN, PRECEDING, CURRENT ROW, AS, IS NOT NULL, BETWEEN

USE injury_risk_predictor;

WITH daily_load AS (
    SELECT
        ts.mm_athlete_id,
        ts.date_id,
        COALESCE(ts.training_load, 0) AS load_val
    FROM fact_training_session ts
    WHERE ts.training_load IS NOT NULL
),
rolling AS (
    SELECT
        dl.mm_athlete_id,
        dl.date_id,
        SUM(dl.load_val) AS daily_load,
        AVG(SUM(dl.load_val)) OVER (
            PARTITION BY dl.mm_athlete_id
            ORDER BY dl.date_id
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS acute_load_7d,
        AVG(SUM(dl.load_val)) OVER (
            PARTITION BY dl.mm_athlete_id
            ORDER BY dl.date_id
            ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
        ) AS chronic_load_28d,
        COUNT(dl.load_val) OVER (
            PARTITION BY dl.mm_athlete_id
            ORDER BY dl.date_id
            ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
        ) AS chronic_n
    FROM daily_load dl
    GROUP BY dl.mm_athlete_id, dl.date_id
)
SELECT
    a.source_id                                                AS athlete_id,
    a.sport_type,
    ag.age_group_label,
    d.full_date,
    ROUND(r.daily_load, 2)                                     AS daily_load,
    ROUND(r.acute_load_7d, 2)                                  AS acute_load_7d,
    ROUND(r.chronic_load_28d, 2)                               AS chronic_load_28d,
    ROUND(r.acute_load_7d / NULLIF(r.chronic_load_28d, 0), 3) AS irs,
    CASE
        WHEN r.chronic_n < 28                                             THEN 'Not enough history'
        WHEN r.acute_load_7d / NULLIF(r.chronic_load_28d, 0) >= 2.0      THEN 'High Risk'
        WHEN r.acute_load_7d / NULLIF(r.chronic_load_28d, 0) >= 1.2      THEN 'Caution'
        WHEN r.acute_load_7d / NULLIF(r.chronic_load_28d, 0) >= 0.8      THEN 'Optimal'
        ELSE 'Underloaded'
    END                                                        AS risk_band,
    SUM(CASE WHEN ts.injury_occurred = 1 THEN 1 ELSE 0 END)   AS injury_flag
FROM rolling r
JOIN dim_athlete_multimodal a  ON a.mm_athlete_id = r.mm_athlete_id
JOIN dim_date d                ON d.date_id        = r.date_id
LEFT JOIN dim_age_group ag     ON ag.age_group_id  = a.age_group_id
LEFT JOIN fact_training_session ts
       ON ts.mm_athlete_id = r.mm_athlete_id
      AND ts.date_id        = r.date_id
WHERE d.full_date BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY
    a.source_id, a.sport_type, ag.age_group_label, d.full_date,
    r.daily_load, r.acute_load_7d, r.chronic_load_28d, r.chronic_n
HAVING r.chronic_load_28d IS NOT NULL
ORDER BY irs DESC
LIMIT 500;
