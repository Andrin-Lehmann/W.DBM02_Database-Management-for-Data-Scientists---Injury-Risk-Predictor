-- 51_create_indexes.sql
-- Re-assert optimization indexes without relying on CREATE INDEX IF NOT EXISTS,
-- which is not portable across all MySQL 8 installations.

USE injury_risk_predictor;

DROP PROCEDURE IF EXISTS create_index_if_missing;

DELIMITER //

CREATE PROCEDURE create_index_if_missing(
    IN p_table_name VARCHAR(64),
    IN p_index_name VARCHAR(64),
    IN p_index_columns VARCHAR(255)
)
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.statistics
        WHERE table_schema = DATABASE()
          AND table_name = p_table_name
          AND index_name = p_index_name
    ) THEN
        SET @ddl = CONCAT(
            'CREATE INDEX `', p_index_name, '` ON `',
            p_table_name, '` (', p_index_columns, ')'
        );
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END//

DELIMITER ;

-- composite: window function partitions on mm_athlete_id, orders by date_id
CALL create_index_if_missing(
    'fact_training_session',
    'idx_ts_athlete_date',
    '`mm_athlete_id`, `date_id`'
);

-- composite: injury lookups by bridge + date
CALL create_index_if_missing(
    'fact_injury_european',
    'idx_inj_bridge_date',
    '`bridge_id`, `date_id`'
);

-- bridge lookups by team; usually already defined inline in the DDL
CALL create_index_if_missing(
    'bridge_player_team',
    'idx_bpt_team',
    '`team_id`'
);

-- covering index: Metabase dashboard filters on risk_band + date range
CALL create_index_if_missing(
    'fact_load_metrics',
    'idx_lm_band_date',
    '`risk_band`, `date_id`'
);

DROP PROCEDURE create_index_if_missing;

ANALYZE TABLE fact_training_session, fact_injury_european, bridge_player_team, fact_load_metrics;
