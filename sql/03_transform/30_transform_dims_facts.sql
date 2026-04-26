-- 30_transform_dims_facts.sql
-- Staging → star schema. Run after 20_load_staging.sql.
-- Order matters: dims before facts, dim_date before fact_injury_european.

USE injury_risk_predictor;

-- facts are rebuildable from staging + dimensions; clear them to keep this
-- transform script safe to rerun during development and grading.
TRUNCATE TABLE fact_load_metrics;
TRUNCATE TABLE fact_training_session;
TRUNCATE TABLE fact_injury_european;
TRUNCATE TABLE fact_university_benchmark;

-- static dims
INSERT INTO dim_age_group (age_group_label, min_age, max_age)
VALUES ('16-20',16,20),('21-24',21,24),('25-29',25,29),
       ('30-34',30,34),('35-39',35,39),('40+',40,99)
ON DUPLICATE KEY UPDATE age_group_label = age_group_label;

INSERT INTO dim_position_group (position_group_code, position_group_name)
VALUES ('GK','Goalkeeper'),('DEF','Defender'),('MID','Midfielder'),('FWD','Forward')
ON DUPLICATE KEY UPDATE position_group_code = position_group_code;

-- dim_team: distinct clubs; INSERT IGNORE respects uq_team_name
INSERT IGNORE INTO dim_team (team_name, league, country)
SELECT DISTINCT TRIM(club), TRIM(league), NULL
FROM stg_european_injuries
WHERE club IS NOT NULL AND TRIM(club) <> '';

-- dim_player_european: distinct names; no team_id here — that lives in bridge_player_team
INSERT IGNORE INTO dim_player_european (player_name, position_group_id, age_group_id)
SELECT DISTINCT
    TRIM(e.player_name),
    pg.position_group_id,
    ag.age_group_id
FROM stg_european_injuries e
JOIN dim_position_group pg ON pg.position_group_code =
    CASE
        WHEN e.player_position = 'Goalkeeper'  THEN 'GK'
        WHEN e.player_position IN ('Centre-Back','Left-Back','Right-Back') THEN 'DEF'
        WHEN e.player_position IN ('Defensive Midfield','Central Midfield','Attacking Midfield',
                                   'Left Midfield','Right Midfield','Midfielder') THEN 'MID'
        WHEN e.player_position IN ('Left Winger','Right Winger','Second Striker','Forward') THEN 'FWD'
        ELSE 'MID'
    END
JOIN dim_age_group ag ON CAST(e.player_age AS UNSIGNED) BETWEEN ag.min_age AND ag.max_age
WHERE e.player_name IS NOT NULL AND TRIM(e.player_name) <> '';

-- bridge_player_team: M:N — one row per player × club × season
INSERT IGNORE INTO bridge_player_team (eu_player_id, team_id, season)
SELECT DISTINCT p.eu_player_id, t.team_id, TRIM(e.season)
FROM stg_european_injuries e
JOIN dim_player_european p ON p.player_name = TRIM(e.player_name)
JOIN dim_team t             ON t.team_name  = TRIM(e.club)
WHERE e.player_name IS NOT NULL AND TRIM(e.player_name) <> ''
  AND e.club IS NOT NULL AND TRIM(e.club) <> '';

-- multimodal prep: cast types, strip NaN strings, assign synthetic dates
-- no real dates exist in this source; session_id order used as day proxy
DROP TABLE IF EXISTS tmp_multimodal_prepared;

CREATE TABLE tmp_multimodal_prepared AS
SELECT
    CAST(NULLIF(TRIM(athlete_id), '') AS UNSIGNED) AS athlete_id,
    CAST(NULLIF(TRIM(session_id), '') AS UNSIGNED) AS session_id_source,
    DATE_ADD('2024-01-01', INTERVAL (
        ROW_NUMBER() OVER (
            PARTITION BY athlete_id
            ORDER BY CAST(NULLIF(TRIM(session_id), '') AS UNSIGNED)
        ) - 1
    ) DAY) AS synthetic_date,
    NULLIF(TRIM(gender),     '') AS gender,
    NULLIF(TRIM(sport_type), '') AS sport_type,
    CAST(NULLIF(TRIM(age), '') AS UNSIGNED) AS age,
    CASE WHEN bmi IS NULL OR TRIM(bmi)='' OR LOWER(TRIM(bmi))='nan'
         THEN NULL ELSE CAST(bmi AS DECIMAL(6,2)) END AS bmi,
    CASE WHEN training_load IS NULL OR TRIM(training_load)='' OR LOWER(TRIM(training_load))='nan'
         THEN NULL ELSE CAST(training_load AS DECIMAL(10,2)) END AS training_load,
    NULLIF(TRIM(training_intensity), '') AS training_intensity,
    CASE WHEN training_duration IS NULL OR TRIM(training_duration)='' OR LOWER(TRIM(training_duration))='nan'
         THEN NULL ELSE CAST(training_duration AS DECIMAL(6,2)) END AS training_duration,
    CASE WHEN fatigue_index IS NULL OR TRIM(fatigue_index)='' OR LOWER(TRIM(fatigue_index))='nan'
         THEN NULL ELSE CAST(fatigue_index AS DECIMAL(5,2)) END AS fatigue_index,
    CASE WHEN injury_occurred IS NULL OR TRIM(injury_occurred)='' THEN 0
         WHEN CAST(injury_occurred AS SIGNED) > 0 THEN 1 ELSE 0 END AS injury_occurred
FROM stg_multimodal_sessions;

-- dim_date: synthetic multimodal dates first, then european real dates
-- european dates must be inserted here — otherwise fact_injury_european rows can't join
INSERT IGNORE INTO dim_date (full_date, year, month, week)
SELECT DISTINCT synthetic_date, YEAR(synthetic_date), MONTH(synthetic_date), WEEK(synthetic_date,3)
FROM tmp_multimodal_prepared
WHERE synthetic_date IS NOT NULL;

INSERT IGNORE INTO dim_date (full_date, year, month, week)
SELECT DISTINCT
    STR_TO_DATE(injury_from_parsed, '%c/%e/%Y'),
    YEAR(STR_TO_DATE(injury_from_parsed,  '%c/%e/%Y')),
    MONTH(STR_TO_DATE(injury_from_parsed, '%c/%e/%Y')),
    WEEK(STR_TO_DATE(injury_from_parsed,  '%c/%e/%Y'), 3)
FROM stg_european_injuries
WHERE injury_from_parsed IS NOT NULL
  AND TRIM(injury_from_parsed) <> ''
  AND STR_TO_DATE(injury_from_parsed, '%c/%e/%Y') IS NOT NULL;

-- dim_athlete_multimodal: source_id = original CSV athlete_id
INSERT INTO dim_athlete_multimodal (source_id, gender, sport_type, age, bmi, age_group_id)
SELECT DISTINCT m.athlete_id, m.gender, m.sport_type, m.age, m.bmi, ag.age_group_id
FROM tmp_multimodal_prepared m
JOIN dim_age_group ag ON m.age BETWEEN ag.min_age AND ag.max_age
ON DUPLICATE KEY UPDATE
    gender = VALUES(gender),
    sport_type = VALUES(sport_type),
    age = VALUES(age),
    bmi = VALUES(bmi),
    age_group_id = VALUES(age_group_id);

-- fact_university_benchmark: S3 benchmark profiles
INSERT INTO fact_university_benchmark
    (age_group_id, position_group_id, training_hours_per_week,
     matches_played_past_season, previous_injury_count, injury_next_season, bmi)
SELECT
    ag.age_group_id,
    pg.position_group_id,
    CAST(u.training_hours_per_week    AS DECIMAL(5,2)),
    CAST(u.matches_played_past_season AS UNSIGNED),
    CAST(u.previous_injury_count      AS UNSIGNED),
    CAST(u.injury_next_season         AS UNSIGNED),
    CAST(u.bmi                        AS DECIMAL(5,2))
FROM stg_university_benchmark u
JOIN dim_age_group ag ON CAST(u.age AS UNSIGNED) BETWEEN ag.min_age AND ag.max_age
JOIN dim_position_group pg ON pg.position_group_code =
    CASE
        WHEN u.position='Goalkeeper' THEN 'GK'
        WHEN u.position='Defender'   THEN 'DEF'
        WHEN u.position='Midfielder' THEN 'MID'
        WHEN u.position='Forward'    THEN 'FWD'
        ELSE 'MID'
    END;

-- fact_injury_european: linked via bridge_id (player + club + season context)
INSERT INTO fact_injury_european (bridge_id, date_id, injury_name, days_absent, games_missed, player_age)
SELECT
    b.bridge_id,
    d.date_id,
    TRIM(e.injury),
    CAST(REGEXP_REPLACE(e.days, '[^0-9]', '') AS UNSIGNED),
    CAST(e.games_missed AS UNSIGNED),
    CAST(e.player_age   AS UNSIGNED)
FROM stg_european_injuries e
JOIN dim_player_european p ON p.player_name = TRIM(e.player_name)
JOIN dim_team t             ON t.team_name  = TRIM(e.club)
JOIN bridge_player_team b   ON b.eu_player_id = p.eu_player_id
                           AND b.team_id      = t.team_id
                           AND b.season       = TRIM(e.season)
JOIN dim_date d             ON d.full_date = STR_TO_DATE(e.injury_from_parsed, '%c/%e/%Y')
WHERE e.player_name IS NOT NULL AND TRIM(e.player_name) <> '';

-- fact_training_session: one row per session
INSERT INTO fact_training_session
    (mm_athlete_id, date_id, session_id_source, training_load,
     training_intensity, training_duration, fatigue_index, injury_occurred)
SELECT
    a.mm_athlete_id, d.date_id, m.session_id_source,
    m.training_load, m.training_intensity, m.training_duration,
    m.fatigue_index, m.injury_occurred
FROM tmp_multimodal_prepared m
JOIN dim_date d                ON d.full_date = m.synthetic_date
JOIN dim_athlete_multimodal a  ON a.source_id  = m.athlete_id;

-- fact_load_metrics: rolling ACWR (IRS) per athlete per session-day
-- IRS stays NULL until the 28-session chronic window is fully populated
INSERT INTO fact_load_metrics
    (mm_athlete_id, date_id, session_load, acute_load_7, chronic_load_28, irs, risk_band)
SELECT
    x.mm_athlete_id, x.date_id, x.session_load,
    x.acute_load_7, x.chronic_load_28,
    CASE WHEN x.chronic_n = 28 AND x.chronic_load_28 > 0
         THEN x.acute_load_7 / x.chronic_load_28 ELSE NULL END AS irs,
    CASE
        WHEN x.chronic_n < 28                                       THEN 'Not enough history'
        WHEN x.chronic_load_28 = 0                                  THEN 'Not calculable'
        WHEN x.acute_load_7 / x.chronic_load_28 >= 2.0             THEN 'High Risk'
        WHEN x.acute_load_7 / x.chronic_load_28 >= 1.2             THEN 'Caution'
        WHEN x.acute_load_7 / x.chronic_load_28 >= 0.8             THEN 'Optimal'
        ELSE 'Underloaded'
    END AS risk_band
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

-- vw_adjusted_irs_by_age_group: cross-source view
-- adjusted_irs = IRS (S1) × prior_injury_multiplier (S3) × position_age_factor (S2)
-- S2 and S3 joined at age_group level only — no shared player identifier exists
CREATE OR REPLACE VIEW vw_adjusted_irs_by_age_group AS
WITH university_factor AS (
    SELECT age_group_id,
           1.0 + (0.3 * AVG(previous_injury_count)) AS prior_injury_multiplier
    FROM fact_university_benchmark
    GROUP BY age_group_id
),
european_group_rates AS (
    SELECT p.age_group_id,
           COUNT(i.injury_id) / COUNT(DISTINCT p.eu_player_id) AS group_injury_rate
    FROM dim_player_european p
    LEFT JOIN bridge_player_team b  ON b.eu_player_id = p.eu_player_id
    LEFT JOIN fact_injury_european i ON i.bridge_id   = b.bridge_id
    GROUP BY p.age_group_id
),
european_avg_rate AS (
    SELECT COUNT(i.injury_id) / COUNT(DISTINCT p.eu_player_id) AS avg_injury_rate
    FROM dim_player_european p
    LEFT JOIN bridge_player_team b  ON b.eu_player_id = p.eu_player_id
    LEFT JOIN fact_injury_european i ON i.bridge_id   = b.bridge_id
),
european_factor AS (
    SELECT egr.age_group_id,
           egr.group_injury_rate / NULLIF(ear.avg_injury_rate, 0) AS position_age_factor
    FROM european_group_rates egr
    CROSS JOIN european_avg_rate ear
)
SELECT
    lm.load_metrics_id,
    lm.mm_athlete_id,
    a.age_group_id,
    ag.age_group_label,
    lm.date_id,
    d.full_date,
    lm.session_load,
    lm.acute_load_7,
    lm.chronic_load_28,
    lm.irs,
    uf.prior_injury_multiplier,
    ef.position_age_factor,
    lm.irs * uf.prior_injury_multiplier * ef.position_age_factor AS adjusted_irs,
    CASE
        WHEN lm.irs IS NULL                                                          THEN 'Not enough history'
        WHEN lm.irs * uf.prior_injury_multiplier * ef.position_age_factor >= 2.0    THEN 'High Risk'
        WHEN lm.irs * uf.prior_injury_multiplier * ef.position_age_factor >= 1.2    THEN 'Caution'
        WHEN lm.irs * uf.prior_injury_multiplier * ef.position_age_factor >= 0.8    THEN 'Optimal'
        ELSE 'Underloaded'
    END AS adjusted_risk_band
FROM fact_load_metrics lm
JOIN dim_athlete_multimodal a  ON a.mm_athlete_id = lm.mm_athlete_id
JOIN dim_age_group ag          ON ag.age_group_id  = a.age_group_id
JOIN dim_date d                ON d.date_id        = lm.date_id
LEFT JOIN university_factor uf ON uf.age_group_id  = a.age_group_id
LEFT JOIN european_factor ef   ON ef.age_group_id  = a.age_group_id;

-- row count check
SELECT 'dim_age_group'        AS tbl, COUNT(*) AS n FROM dim_age_group
UNION ALL SELECT 'dim_position_group',  COUNT(*) FROM dim_position_group
UNION ALL SELECT 'dim_team',            COUNT(*) FROM dim_team
UNION ALL SELECT 'dim_date',            COUNT(*) FROM dim_date
UNION ALL SELECT 'dim_player_european', COUNT(*) FROM dim_player_european
UNION ALL SELECT 'bridge_player_team',  COUNT(*) FROM bridge_player_team
UNION ALL SELECT 'dim_athlete_multimodal', COUNT(*) FROM dim_athlete_multimodal
UNION ALL SELECT 'fact_university_benchmark', COUNT(*) FROM fact_university_benchmark
UNION ALL SELECT 'fact_injury_european', COUNT(*) FROM fact_injury_european
UNION ALL SELECT 'fact_training_session', COUNT(*) FROM fact_training_session
UNION ALL SELECT 'fact_load_metrics',   COUNT(*) FROM fact_load_metrics;

DROP TABLE IF EXISTS tmp_multimodal_prepared;
