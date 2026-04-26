USE injury_risk_predictor;

ALTER TABLE fact_load_metrics MODIFY risk_band VARCHAR(20) DEFAULT NULL;

TRUNCATE TABLE fact_load_metrics;

INSERT INTO fact_load_metrics
    (mm_athlete_id, date_id, session_load, acute_load_7, chronic_load_28, irs, risk_band)
SELECT
    x.mm_athlete_id, x.date_id, x.session_load,
    x.acute_load_7, x.chronic_load_28,
    CASE WHEN x.chronic_n = 28 AND x.chronic_load_28 > 0
         THEN x.acute_load_7 / x.chronic_load_28 ELSE NULL END,
    CASE
        WHEN x.chronic_n < 28                               THEN 'Not enough history'
        WHEN x.chronic_load_28 = 0                          THEN 'Not calculable'
        WHEN x.acute_load_7 / x.chronic_load_28 >= 2.0     THEN 'High Risk'
        WHEN x.acute_load_7 / x.chronic_load_28 >= 1.2     THEN 'Caution'
        WHEN x.acute_load_7 / x.chronic_load_28 >= 0.8     THEN 'Optimal'
        ELSE 'Underloaded'
    END
FROM (
    SELECT
        ts.mm_athlete_id,
        ts.date_id,
        ts.training_load AS session_load,
        AVG(ts.training_load) OVER (
            PARTITION BY ts.mm_athlete_id ORDER BY d.full_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS acute_load_7,
        AVG(ts.training_load) OVER (
            PARTITION BY ts.mm_athlete_id ORDER BY d.full_date
            ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
        ) AS chronic_load_28,
        COUNT(ts.training_load) OVER (
            PARTITION BY ts.mm_athlete_id ORDER BY d.full_date
            ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
        ) AS chronic_n
    FROM fact_training_session ts
    JOIN dim_date d ON d.date_id = ts.date_id
) x;

SELECT risk_band, COUNT(*) AS cnt FROM fact_load_metrics GROUP BY risk_band ORDER BY cnt DESC;
