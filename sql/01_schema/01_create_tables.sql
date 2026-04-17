-- =============================================================================
-- Injury Risk Predictor — Physical Schema (3NF)
-- Module: DBM HSLU
-- =============================================================================
-- Design notes:
--   * 8 entities (>= 5 required)
--   * One M:N relationship: Player <-> Match via Appearance
--   * 15+ attributes across the schema
--   * Surrogate INT AUTO_INCREMENT PKs everywhere for ELT stability
--   * InnoDB with utf8mb4 for Unicode-safe player names
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------------
-- Dimension: Date
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_date` (
  `date_id`   INT         NOT NULL AUTO_INCREMENT,
  `full_date` DATE        NOT NULL,
  `year`      SMALLINT    NOT NULL,
  `quarter`   TINYINT     NOT NULL,
  `month`     TINYINT     NOT NULL,
  `week`      TINYINT     NOT NULL,
  `day`       TINYINT     NOT NULL,
  `dow`       TINYINT     NOT NULL,  -- day-of-week 1..7
  PRIMARY KEY (`date_id`),
  UNIQUE KEY `uq_full_date` (`full_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Dimension: Team
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_team` (
  `team_id`       INT          NOT NULL AUTO_INCREMENT,
  `team_name`     VARCHAR(128) NOT NULL,
  `country`       VARCHAR(64)  DEFAULT NULL,
  `league`        VARCHAR(64)  DEFAULT NULL,
  PRIMARY KEY (`team_id`),
  UNIQUE KEY `uq_team_name` (`team_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Dimension: Position
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_position` (
  `position_id`    INT         NOT NULL AUTO_INCREMENT,
  `position_code`  VARCHAR(8)  NOT NULL,   -- GK, DEF, MID, FWD
  `position_name`  VARCHAR(32) NOT NULL,
  PRIMARY KEY (`position_id`),
  UNIQUE KEY `uq_position_code` (`position_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Dimension: Player
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_player` (
  `player_id`       INT          NOT NULL AUTO_INCREMENT,
  `player_name`     VARCHAR(128) NOT NULL,
  `team_id`         INT          DEFAULT NULL,
  `position_id`     INT          DEFAULT NULL,
  `date_of_birth`   DATE         DEFAULT NULL,
  `height_cm`       DECIMAL(5,2) DEFAULT NULL,
  `weight_kg`       DECIMAL(5,2) DEFAULT NULL,
  `prior_injuries`  INT          DEFAULT 0,
  PRIMARY KEY (`player_id`),
  UNIQUE KEY `uq_player_name_team` (`player_name`, `team_id`),
  KEY `idx_team_id`     (`team_id`),
  KEY `idx_position_id` (`position_id`),
  CONSTRAINT `fk_player_team`     FOREIGN KEY (`team_id`)     REFERENCES `dim_team`     (`team_id`),
  CONSTRAINT `fk_player_position` FOREIGN KEY (`position_id`) REFERENCES `dim_position` (`position_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Fact: Training Session (1:N from Player)
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_training_session` (
  `session_id`          INT          NOT NULL AUTO_INCREMENT,
  `player_id`           INT          NOT NULL,
  `date_id`             INT          NOT NULL,
  `rpe`                 DECIMAL(4,1) DEFAULT NULL,  -- Rate of Perceived Exertion (0-10)
  `duration_min`        SMALLINT     DEFAULT NULL,
  `total_distance_m`    DECIMAL(8,1) DEFAULT NULL,
  `hsr_distance_m`      DECIMAL(7,1) DEFAULT NULL,  -- high-speed running
  `sprint_count`        SMALLINT     DEFAULT NULL,
  `accelerations`       SMALLINT     DEFAULT NULL,
  `decelerations`       SMALLINT     DEFAULT NULL,
  `avg_hr_bpm`          SMALLINT     DEFAULT NULL,
  `max_hr_bpm`          SMALLINT     DEFAULT NULL,
  PRIMARY KEY (`session_id`),
  KEY `idx_session_player_date` (`player_id`, `date_id`),
  KEY `idx_session_date`        (`date_id`),
  CONSTRAINT `fk_session_player` FOREIGN KEY (`player_id`) REFERENCES `dim_player` (`player_id`),
  CONSTRAINT `fk_session_date`   FOREIGN KEY (`date_id`)   REFERENCES `dim_date`   (`date_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Fact: Match (the 'one' side before we add the bridge)
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_match` (
  `match_id`      INT NOT NULL AUTO_INCREMENT,
  `date_id`       INT NOT NULL,
  `home_team_id`  INT NOT NULL,
  `away_team_id`  INT NOT NULL,
  `home_goals`    TINYINT DEFAULT NULL,
  `away_goals`    TINYINT DEFAULT NULL,
  `competition`   VARCHAR(64) DEFAULT NULL,
  PRIMARY KEY (`match_id`),
  KEY `idx_match_date`       (`date_id`),
  KEY `idx_match_home_team`  (`home_team_id`),
  KEY `idx_match_away_team`  (`away_team_id`),
  CONSTRAINT `fk_match_date`       FOREIGN KEY (`date_id`)      REFERENCES `dim_date` (`date_id`),
  CONSTRAINT `fk_match_home_team`  FOREIGN KEY (`home_team_id`) REFERENCES `dim_team` (`team_id`),
  CONSTRAINT `fk_match_away_team`  FOREIGN KEY (`away_team_id`) REFERENCES `dim_team` (`team_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Bridge: Appearance  (the M:N relationship between Player and Match)
-- ---------------------------------------------------------------------------
CREATE TABLE `bridge_appearance` (
  `appearance_id`     INT NOT NULL AUTO_INCREMENT,
  `player_id`         INT NOT NULL,
  `match_id`          INT NOT NULL,
  `minutes_played`    SMALLINT DEFAULT NULL,
  `distance_covered_m` DECIMAL(8,1) DEFAULT NULL,
  `match_rpe`         DECIMAL(4,1) DEFAULT NULL,
  PRIMARY KEY (`appearance_id`),
  UNIQUE KEY `uq_player_match` (`player_id`, `match_id`),
  KEY `idx_appearance_match` (`match_id`),
  CONSTRAINT `fk_appearance_player` FOREIGN KEY (`player_id`) REFERENCES `dim_player` (`player_id`),
  CONSTRAINT `fk_appearance_match`  FOREIGN KEY (`match_id`)  REFERENCES `fact_match` (`match_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Fact: Injury (1:N from Player)
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_injury` (
  `injury_id`        INT          NOT NULL AUTO_INCREMENT,
  `player_id`        INT          NOT NULL,
  `date_id`          INT          NOT NULL,
  `injury_type`      VARCHAR(64)  DEFAULT NULL,  -- muscle, joint, ligament, ...
  `body_region`      VARCHAR(64)  DEFAULT NULL,  -- hamstring, knee, ankle, ...
  `severity`         VARCHAR(16)  DEFAULT NULL,  -- minor | moderate | severe
  `absence_days`     SMALLINT     DEFAULT NULL,
  `context`          VARCHAR(16)  DEFAULT NULL,  -- training | match
  PRIMARY KEY (`injury_id`),
  KEY `idx_injury_player_date` (`player_id`, `date_id`),
  CONSTRAINT `fk_injury_player` FOREIGN KEY (`player_id`) REFERENCES `dim_player` (`player_id`),
  CONSTRAINT `fk_injury_date`   FOREIGN KEY (`date_id`)   REFERENCES `dim_date`   (`date_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Fact: LoadMetrics  (materialized summary, refreshed by script 52)
-- Holds the pre-computed acute/chronic loads and the IRS band.
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_load_metrics` (
  `load_metrics_id` INT           NOT NULL AUTO_INCREMENT,
  `player_id`       INT           NOT NULL,
  `date_id`         INT           NOT NULL,
  `daily_load`      DECIMAL(10,2) DEFAULT NULL,
  `acute_load_7d`   DECIMAL(10,2) DEFAULT NULL,
  `chronic_load_28d` DECIMAL(10,2) DEFAULT NULL,
  `irs`             DECIMAL(6,3)  DEFAULT NULL,
  `risk_band`       VARCHAR(16)   DEFAULT NULL,  -- high | optimal | under
  PRIMARY KEY (`load_metrics_id`),
  UNIQUE KEY `uq_load_player_date` (`player_id`, `date_id`),
  KEY `idx_load_date` (`date_id`),
  CONSTRAINT `fk_load_player` FOREIGN KEY (`player_id`) REFERENCES `dim_player` (`player_id`),
  CONSTRAINT `fk_load_date`   FOREIGN KEY (`date_id`)   REFERENCES `dim_date`   (`date_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET FOREIGN_KEY_CHECKS = 1;
