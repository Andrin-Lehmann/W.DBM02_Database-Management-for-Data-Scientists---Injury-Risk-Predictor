-- =============================================================================
-- Injury Risk Predictor — Physical Schema (3NF)
-- Module: DBM HSLU
-- =============================================================================
-- Source datasets:
--   S1: multimodal_sports_injury_dataset.csv  (anonymous athletes, training sessions)
--   S2: full_dataset_thesis - 1.csv           (named European players, injury records)
--   S3: data.csv                              (anonymous benchmark profiles, University)
--
-- Integration strategy:
--   No shared player-level identifier exists across S1, S2, S3.
--   Integration via conformed dimensions: dim_age_group + dim_position_group.
--
-- Design notes (Rubric compliance):
--   * 11 entities  (>= 5 required)
--   * 1 M:N relationship: Player <-> Team via bridge_player_team  (Rule R3)
--   * Multiple 1:N relationships throughout  (Rule R4)
--   * 25+ attributes across the schema  (>= 15 required)
--   * Third Normal Form throughout
--   * Surrogate INT AUTO_INCREMENT PKs for ELT stability
--   * InnoDB / utf8mb4
-- =============================================================================

USE injury_risk_predictor;

SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------------
-- Conformed Dimension: Age Group  (shared by S1, S2, S3)
-- Enables cross-source comparison at age-band level.
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_age_group` (
  `age_group_id`    INT         NOT NULL AUTO_INCREMENT,
  `age_group_label` VARCHAR(16) NOT NULL,  -- e.g. '18-20', '21-24', '25-29', '30+'
  `min_age`         TINYINT     NOT NULL,
  `max_age`         TINYINT     DEFAULT NULL,  -- NULL = no upper bound (30+)
  PRIMARY KEY (`age_group_id`),
  UNIQUE KEY `uq_age_group_label` (`age_group_label`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Conformed Dimension: Position Group  (shared by S2, S3)
-- Enables cross-source comparison at position level.
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_position_group` (
  `position_group_id`   INT        NOT NULL AUTO_INCREMENT,
  `position_group_code` VARCHAR(8) NOT NULL,  -- GK | DEF | MID | FWD
  `position_group_name` VARCHAR(32) NOT NULL,
  PRIMARY KEY (`position_group_id`),
  UNIQUE KEY `uq_position_group_code` (`position_group_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Shared Dimension: Date  (used by S2 real dates + S1 synthetic dates)
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_date` (
  `date_id`   INT      NOT NULL AUTO_INCREMENT,
  `full_date` DATE     NOT NULL,
  `year`      SMALLINT NOT NULL,
  `month`     TINYINT  NOT NULL,
  `week`      TINYINT  NOT NULL,
  PRIMARY KEY (`date_id`),
  UNIQUE KEY `uq_full_date` (`full_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S1 | Dimension: Athlete Multimodal
-- One row per anonymous athlete from multimodal_sports_injury_dataset.csv.
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_athlete_multimodal` (
  `mm_athlete_id` INT         NOT NULL AUTO_INCREMENT,
  `source_id`     INT         NOT NULL,        -- original athlete_id in CSV
  `gender`        VARCHAR(16) DEFAULT NULL,
  `sport_type`    VARCHAR(64) DEFAULT NULL,
  `age`           TINYINT     DEFAULT NULL,
  `bmi`           DECIMAL(5,2) DEFAULT NULL,
  `age_group_id`  INT         DEFAULT NULL,    -- FK → dim_age_group
  PRIMARY KEY (`mm_athlete_id`),
  UNIQUE KEY `uq_source_id` (`source_id`),
  KEY `idx_mm_athlete_age_group` (`age_group_id`),
  CONSTRAINT `fk_mm_athlete_age_group`
    FOREIGN KEY (`age_group_id`) REFERENCES `dim_age_group` (`age_group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S1 | Fact: Training Session
-- One row per training session from multimodal_sports_injury_dataset.csv.
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_training_session` (
  `training_session_id` INT          NOT NULL AUTO_INCREMENT,
  `mm_athlete_id`       INT          NOT NULL,  -- FK → dim_athlete_multimodal
  `date_id`             INT          DEFAULT NULL,  -- FK → dim_date (synthetic)
  `session_id_source`   INT          NOT NULL,  -- original session_id in CSV
  `training_load`       DECIMAL(8,2) DEFAULT NULL,
  `training_intensity`  VARCHAR(32)  DEFAULT NULL,
  `training_duration`   DECIMAL(6,2) DEFAULT NULL,
  `fatigue_index`       DECIMAL(5,2) DEFAULT NULL,
  `injury_occurred`     TINYINT(1)   DEFAULT NULL,  -- 0 = no, 1 = yes
  PRIMARY KEY (`training_session_id`),
  KEY `idx_ts_athlete`  (`mm_athlete_id`),
  KEY `idx_ts_date`     (`date_id`),
  CONSTRAINT `fk_ts_athlete`
    FOREIGN KEY (`mm_athlete_id`) REFERENCES `dim_athlete_multimodal` (`mm_athlete_id`),
  CONSTRAINT `fk_ts_date`
    FOREIGN KEY (`date_id`) REFERENCES `dim_date` (`date_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S1 | Derived: Load Metrics  (session-based IRS)
-- Computed via INSERT...SELECT (ELT).
-- Acute load  = AVG(training_load) over last 7 sessions per athlete
-- Chronic load = AVG(training_load) over last 28 sessions per athlete
-- IRS = acute_load_7 / chronic_load_28
-- Decision rule: IRS >= 1.5 → high | 0.8-1.5 → optimal | < 0.8 → under
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_load_metrics` (
  `load_metrics_id` INT           NOT NULL AUTO_INCREMENT,
  `mm_athlete_id`   INT           NOT NULL,  -- FK → dim_athlete_multimodal
  `date_id`         INT           DEFAULT NULL,  -- FK → dim_date (synthetic)
  `session_load`    DECIMAL(8,2)  DEFAULT NULL,
  `acute_load_7`    DECIMAL(10,2) DEFAULT NULL,
  `chronic_load_28` DECIMAL(10,2) DEFAULT NULL,
  `irs`             DECIMAL(6,3)  DEFAULT NULL,
  `risk_band`       VARCHAR(16)   DEFAULT NULL,  -- high | optimal | under
  PRIMARY KEY (`load_metrics_id`),
  KEY `idx_lm_athlete` (`mm_athlete_id`),
  KEY `idx_lm_date`    (`date_id`),
  CONSTRAINT `fk_lm_athlete`
    FOREIGN KEY (`mm_athlete_id`) REFERENCES `dim_athlete_multimodal` (`mm_athlete_id`),
  CONSTRAINT `fk_lm_date`
    FOREIGN KEY (`date_id`) REFERENCES `dim_date` (`date_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S2 | Dimension: Team
-- One row per club from full_dataset_thesis - 1.csv.
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_team` (
  `team_id`   INT          NOT NULL AUTO_INCREMENT,
  `team_name` VARCHAR(128) NOT NULL,
  `league`    VARCHAR(64)  DEFAULT NULL,
  `country`   VARCHAR(64)  DEFAULT NULL,
  PRIMARY KEY (`team_id`),
  UNIQUE KEY `uq_team_name` (`team_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S2 | Dimension: Player European
-- One row per named European player from full_dataset_thesis - 1.csv.
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_player_european` (
  `eu_player_id`      INT          NOT NULL AUTO_INCREMENT,
  `player_name`       VARCHAR(128) NOT NULL,
  `position_group_id` INT          DEFAULT NULL,  -- FK → dim_position_group
  `age_group_id`      INT          DEFAULT NULL,  -- FK → dim_age_group
  PRIMARY KEY (`eu_player_id`),
  UNIQUE KEY `uq_eu_player_name` (`player_name`),
  KEY `idx_eu_player_position` (`position_group_id`),
  KEY `idx_eu_player_age`      (`age_group_id`),
  CONSTRAINT `fk_eu_player_position`
    FOREIGN KEY (`position_group_id`) REFERENCES `dim_position_group` (`position_group_id`),
  CONSTRAINT `fk_eu_player_age`
    FOREIGN KEY (`age_group_id`) REFERENCES `dim_age_group` (`age_group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S2 | Bridge: Player <-> Team  [M:N]                             (Rule R3)
-- A player can play for multiple teams across seasons;
-- a team has multiple players each season.
-- ---------------------------------------------------------------------------
CREATE TABLE `bridge_player_team` (
  `bridge_id`   INT        NOT NULL AUTO_INCREMENT,
  `eu_player_id` INT       NOT NULL,  -- FK → dim_player_european
  `team_id`     INT        NOT NULL,  -- FK → dim_team
  `season`      VARCHAR(8) NOT NULL,  -- e.g. '20/21'
  PRIMARY KEY (`bridge_id`),
  UNIQUE KEY `uq_player_team_season` (`eu_player_id`, `team_id`, `season`),
  KEY `idx_bpt_team` (`team_id`),
  CONSTRAINT `fk_bpt_player`
    FOREIGN KEY (`eu_player_id`) REFERENCES `dim_player_european` (`eu_player_id`),
  CONSTRAINT `fk_bpt_team`
    FOREIGN KEY (`team_id`) REFERENCES `dim_team` (`team_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S2 | Fact: Injury European
-- One row per injury event from full_dataset_thesis - 1.csv.
-- References bridge_player_team to capture player + team + season context.
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_injury_european` (
  `injury_id`   INT          NOT NULL AUTO_INCREMENT,
  `bridge_id`   INT          NOT NULL,  -- FK → bridge_player_team
  `date_id`     INT          DEFAULT NULL,  -- FK → dim_date (injury start date)
  `injury_name` VARCHAR(128) DEFAULT NULL,
  `days_absent` SMALLINT     DEFAULT NULL,
  `games_missed` SMALLINT    DEFAULT NULL,
  `player_age`  TINYINT      DEFAULT NULL,  -- age at time of injury
  PRIMARY KEY (`injury_id`),
  KEY `idx_inj_bridge` (`bridge_id`),
  KEY `idx_inj_date`   (`date_id`),
  CONSTRAINT `fk_inj_bridge`
    FOREIGN KEY (`bridge_id`) REFERENCES `bridge_player_team` (`bridge_id`),
  CONSTRAINT `fk_inj_date`
    FOREIGN KEY (`date_id`) REFERENCES `dim_date` (`date_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S3 | Fact: University Benchmark
-- One row per anonymous player profile from data.csv.
-- Benchmark reference: injury risk by age group and position group.
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_university_benchmark` (
  `university_row_id`          INT          NOT NULL AUTO_INCREMENT,
  `age_group_id`               INT          DEFAULT NULL,  -- FK → dim_age_group
  `position_group_id`          INT          DEFAULT NULL,  -- FK → dim_position_group
  `training_hours_per_week`    DECIMAL(5,2) DEFAULT NULL,
  `matches_played_past_season` SMALLINT     DEFAULT NULL,
  `previous_injury_count`      SMALLINT     DEFAULT NULL,
  `injury_next_season`         TINYINT(1)   DEFAULT NULL,  -- 0 = no, 1 = yes
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
