-- 20_load_staging.sql
-- Raw CSVs → all-TEXT staging tables. No casting here; types enforced in step 30.
-- Update the three file paths to your data/raw/ location before running.

SET GLOBAL local_infile = 1;
USE injury_risk_predictor;

DROP TABLE IF EXISTS stg_university_benchmark;
DROP TABLE IF EXISTS stg_european_injuries;
DROP TABLE IF EXISTS stg_multimodal_sessions;

CREATE TABLE stg_european_injuries (
    season               TEXT,
    injury               TEXT,
    days                 TEXT,
    games_missed         TEXT,
    injury_from_parsed   TEXT,
    injury_until_parsed  TEXT,
    player_name          TEXT,
    player_age           TEXT,
    player_position      TEXT,
    club                 TEXT,
    league               TEXT
);

CREATE TABLE stg_multimodal_sessions (
    athlete_id            TEXT,
    heart_rate            TEXT,
    body_temperature      TEXT,
    hydration_level       TEXT,
    sleep_quality         TEXT,
    recovery_score        TEXT,
    stress_level          TEXT,
    muscle_activity       TEXT,
    joint_angles          TEXT,
    gait_speed            TEXT,
    cadence               TEXT,
    step_count            TEXT,
    jump_height           TEXT,
    ground_reaction_force TEXT,
    range_of_motion       TEXT,
    ambient_temperature   TEXT,
    humidity              TEXT,
    altitude              TEXT,
    playing_surface       TEXT,
    training_intensity    TEXT,
    training_duration     TEXT,
    training_load         TEXT,
    fatigue_index         TEXT,
    injury_occurred       TEXT,
    session_id            TEXT,
    sport_type            TEXT,
    gender                TEXT,
    age                   TEXT,
    bmi                   TEXT
);

CREATE TABLE stg_university_benchmark (
    age                        TEXT,
    height_cm                  TEXT,
    weight_kg                  TEXT,
    position                   TEXT,
    training_hours_per_week    TEXT,
    matches_played_past_season TEXT,
    previous_injury_count      TEXT,
    knee_strength_score        TEXT,
    hamstring_flexibility      TEXT,
    reaction_time_ms           TEXT,
    balance_test_score         TEXT,
    sprint_speed_10m_s         TEXT,
    agility_score              TEXT,
    sleep_hours_per_night      TEXT,
    stress_level_score         TEXT,
    nutrition_quality_score    TEXT,
    warmup_routine_adherence   TEXT,
    injury_next_season         TEXT,
    bmi                        TEXT
);

LOAD DATA LOCAL INFILE 'C:/DBM/injury-risk-predictor/data/raw/full_dataset_thesis - 1.csv'
INTO TABLE stg_european_injuries
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(season, injury, days, games_missed, injury_from_parsed, injury_until_parsed,
 player_name, player_age, player_position, club, league);

LOAD DATA LOCAL INFILE 'C:/DBM/injury-risk-predictor/data/raw/multimodal_sports_injury_dataset.csv'
INTO TABLE stg_multimodal_sessions
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(athlete_id, heart_rate, body_temperature, hydration_level, sleep_quality,
 recovery_score, stress_level, muscle_activity, joint_angles, gait_speed,
 cadence, step_count, jump_height, ground_reaction_force, range_of_motion,
 ambient_temperature, humidity, altitude, playing_surface, training_intensity,
 training_duration, training_load, fatigue_index, injury_occurred, session_id,
 sport_type, gender, age, bmi);

LOAD DATA LOCAL INFILE 'C:/DBM/injury-risk-predictor/data/raw/data.csv'
INTO TABLE stg_university_benchmark
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(age, height_cm, weight_kg, position, training_hours_per_week,
 matches_played_past_season, previous_injury_count, knee_strength_score,
 hamstring_flexibility, reaction_time_ms, balance_test_score,
 sprint_speed_10m_s, agility_score, sleep_hours_per_night,
 stress_level_score, nutrition_quality_score, warmup_routine_adherence,
 injury_next_season, bmi);

SELECT 'stg_european_injuries'  AS staging_table, COUNT(*) AS rows_loaded FROM stg_european_injuries
UNION ALL
SELECT 'stg_multimodal_sessions',                  COUNT(*) FROM stg_multimodal_sessions
UNION ALL
SELECT 'stg_university_benchmark',                 COUNT(*) FROM stg_university_benchmark;
