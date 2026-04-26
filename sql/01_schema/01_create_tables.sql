-- 01_create_tables.sql
-- Star schema for injury_risk_predictor.
-- 3NF, InnoDB, utf8mb4. Surrogate PKs throughout for ELT stability.
-- S1 = multimodal, S2 = european, S3 = university

USE injury_risk_predictor;

SET FOREIGN_KEY_CHECKS = 0;

-- conformed dim shared by all three sources
CREATE TABLE `dim_age_group` (
  `age_group_id`    INT         NOT NULL AUTO_INCREMENT,
  `age_group_label` VARCHAR(16) NOT NULL,
  `min_age`         TINYINT     NOT NULL,
  `max_age`         TINYINT     DEFAULT NULL,
  PRIMARY KEY (`age_group_id`),
  UNIQUE KEY `uq_age_group_label` (`age_group_label`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- conformed dim shared by S2 + S3 (S1 has no position field)
CREATE TABLE `dim_position_group` (
  `position_group_id`   INT         NOT NULL AUTO_INCREMENT,
  `position_group_code` VARCHAR(8)  NOT NULL,  -- GK | DEF | MID | FWD
  `position_group_name` VARCHAR(32) NOT NULL,
  PRIMARY KEY (`position_group_id`),
  UNIQUE KEY `uq_position_group_code` (`position_group_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- shared by S2 real dates and S1 synthetic dates
CREATE TABLE `dim_date` (
  `date_id`   INT      NOT NULL AUTO_INCREMENT,
  `full_date` DATE     NOT NULL,
  `year`      SMALLINT NOT NULL,
  `month`     TINYINT  NOT NULL,
  `week`      TINYINT  NOT NULL,
  PRIMARY KEY (`date_id`),
  UNIQUE KEY `uq_full_date` (`full_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- S1: one row per anonymous athlete; source_id = original CSV athlete_id
CREATE TABLE `dim_athlete_multimodal` (
  `mm_athlete_id` INT          NOT NULL AUTO_INCREMENT,
  `source_id`     INT          NOT NULL,
  `gender`        VARCHAR(16)  DEFAULT NULL,
  `sport_type`    VARCHAR(64)  DEFAULT NULL,
  `age`           TINYINT      DEFAULT NULL,
  `bmi`           DECIMAL(5,2) DEFAULT NULL,
  `age_group_id`  INT          DEFAULT NULL,
  PRIMARY KEY (`mm_athlete_id`),
  UNIQUE KEY `uq_source_id` (`source_id`),
  KEY `idx_mm_athlete_age_group` (`age_group_id`),
  CONSTRAINT `fk_mm_athlete_age_group`
    FOREIGN KEY (`age_group_id`) REFERENCES `dim_age_group` (`age_group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- S1: one row per training session
CREATE TABLE `fact_training_session` (
  `training_session_id` INT          NOT NULL AUTO_INCREMENT,
  `mm_athlete_id`       INT          NOT NULL,
  `date_id`             INT          DEFAULT NULL,  -- synthetic date
  `session_id_source`   INT          NOT NULL,
  `training_load`       DECIMAL(8,2) DEFAULT NULL,
  `training_intensity`  VARCHAR(32)  DEFAULT NULL,
  `training_duration`   DECIMAL(6,2) DEFAULT NULL,
  `fatigue_index`       DECIMAL(5,2) DEFAULT NULL,
  `injury_occurred`     TINYINT(1)   DEFAULT NULL,
  PRIMARY KEY (`training_session_id`),
  KEY `idx_ts_athlete` (`mm_athlete_id`),
  KEY `idx_ts_date`    (`date_id`),
  CONSTRAINT `fk_ts_athlete`
    FOREIGN KEY (`mm_athlete_id`) REFERENCES `dim_athlete_multimodal` (`mm_athlete_id`),
  CONSTRAINT `fk_ts_date`
    FOREIGN KEY (`date_id`) REFERENCES `dim_date` (`date_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- S1 derived: rolling ACWR per athlete per day; populated by ELT, not live
-- IRS = acute_load_7 / chronic_load_28; NULL until 28-session window fills
CREATE TABLE `fact_load_metrics` (
  `load_metrics_id` INT           NOT NULL AUTO_INCREMENT,
  `mm_athlete_id`   INT           NOT NULL,
  `date_id`         INT           DEFAULT NULL,
  `session_load`    DECIMAL(8,2)  DEFAULT NULL,
  `acute_load_7`    DECIMAL(10,2) DEFAULT NULL,
  `chronic_load_28` DECIMAL(10,2) DEFAULT NULL,
  `irs`             DECIMAL(6,3)  DEFAULT NULL,
  `risk_band`       VARCHAR(20)   DEFAULT NULL,
  PRIMARY KEY (`load_metrics_id`),
  KEY `idx_lm_athlete`  (`mm_athlete_id`),
  KEY `idx_lm_date`     (`date_id`),
  KEY `idx_lm_band_date`(`risk_band`, `date_id`),
  CONSTRAINT `fk_lm_athlete`
    FOREIGN KEY (`mm_athlete_id`) REFERENCES `dim_athlete_multimodal` (`mm_athlete_id`),
  CONSTRAINT `fk_lm_date`
    FOREIGN KEY (`date_id`) REFERENCES `dim_date` (`date_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- S2: one row per club
CREATE TABLE `dim_team` (
  `team_id`   INT          NOT NULL AUTO_INCREMENT,
  `team_name` VARCHAR(128) NOT NULL,
  `league`    VARCHAR(64)  DEFAULT NULL,
  `country`   VARCHAR(64)  DEFAULT NULL,
  PRIMARY KEY (`team_id`),
  UNIQUE KEY `uq_team_name` (`team_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- S2: one row per distinct player name; team link via bridge (M:N)
CREATE TABLE `dim_player_european` (
  `eu_player_id`      INT          NOT NULL AUTO_INCREMENT,
  `player_name`       VARCHAR(128) NOT NULL,
  `position_group_id` INT          DEFAULT NULL,
  `age_group_id`      INT          DEFAULT NULL,
  PRIMARY KEY (`eu_player_id`),
  UNIQUE KEY `uq_eu_player_name` (`player_name`),
  KEY `idx_eu_player_position` (`position_group_id`),
  KEY `idx_eu_player_age`      (`age_group_id`),
  CONSTRAINT `fk_eu_player_position`
    FOREIGN KEY (`position_group_id`) REFERENCES `dim_position_group` (`position_group_id`),
  CONSTRAINT `fk_eu_player_age`
    FOREIGN KEY (`age_group_id`) REFERENCES `dim_age_group` (`age_group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- S2: M:N bridge — player can play for multiple clubs across seasons
CREATE TABLE `bridge_player_team` (
  `bridge_id`    INT        NOT NULL AUTO_INCREMENT,
  `eu_player_id` INT        NOT NULL,
  `team_id`      INT        NOT NULL,
  `season`       VARCHAR(8) NOT NULL,
  PRIMARY KEY (`bridge_id`),
  UNIQUE KEY `uq_player_team_season` (`eu_player_id`, `team_id`, `season`),
  KEY `idx_bpt_team` (`team_id`),
  CONSTRAINT `fk_bpt_player`
    FOREIGN KEY (`eu_player_id`) REFERENCES `dim_player_european` (`eu_player_id`),
  CONSTRAINT `fk_bpt_team`
    FOREIGN KEY (`team_id`) REFERENCES `dim_team` (`team_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- S2: one row per injury event; player+team+season context via bridge_id
CREATE TABLE `fact_injury_european` (
  `injury_id`    INT          NOT NULL AUTO_INCREMENT,
  `bridge_id`    INT          NOT NULL,
  `date_id`      INT          DEFAULT NULL,
  `injury_name`  VARCHAR(128) DEFAULT NULL,
  `days_absent`  SMALLINT     DEFAULT NULL,
  `games_missed` SMALLINT     DEFAULT NULL,
  `player_age`   TINYINT      DEFAULT NULL,
  PRIMARY KEY (`injury_id`),
  KEY `idx_inj_bridge` (`bridge_id`),
  KEY `idx_inj_date`   (`date_id`),
  CONSTRAINT `fk_inj_bridge`
    FOREIGN KEY (`bridge_id`) REFERENCES `bridge_player_team` (`bridge_id`),
  CONSTRAINT `fk_inj_date`
    FOREIGN KEY (`date_id`) REFERENCES `dim_date` (`date_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- S3: anonymous player profiles; used as benchmark only, no player-level join to S1/S2
CREATE TABLE `fact_university_benchmark` (
  `university_row_id`          INT          NOT NULL AUTO_INCREMENT,
  `age_group_id`               INT          DEFAULT NULL,
  `position_group_id`          INT          DEFAULT NULL,
  `training_hours_per_week`    DECIMAL(5,2) DEFAULT NULL,
  `matches_played_past_season` SMALLINT     DEFAULT NULL,
  `previous_injury_count`      SMALLINT     DEFAULT NULL,
  `injury_next_season`         TINYINT(1)   DEFAULT NULL,
  `bmi`                        DECIMAL(5,2) DEFAULT NULL,
  PRIMARY KEY (`university_row_id`),
  KEY `idx_ub_age_group`      (`age_group_id`),
  KEY `idx_ub_position_group` (`position_group_id`),
  CONSTRAINT `fk_ub_age_group`
    FOREIGN KEY (`age_group_id`) REFERENCES `dim_age_group` (`age_group_id`),
  CONSTRAINT `fk_ub_position_group`
    FOREIGN KEY (`position_group_id`) REFERENCES `dim_position_group` (`position_group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET FOREIGN_KEY_CHECKS = 1;
