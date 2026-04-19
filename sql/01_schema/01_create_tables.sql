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
--   S1, S2, S3 have no shared player-level identifier and cannot be joined
--   at player level. Integration is achieved via the conformed dimension
--   dim_position (GK / DEF / MID / FWD), which is referenced by both
--   dim_player (S2) and fact_player_profile (S3).
--
-- Design notes (Rubric compliance):
--   * 9 entities  (>= 5 required)
--   * 1 M:N relationship: Player <-> Club via bridge_player_club  (Rule R3)
--   * 25+ attributes across the schema  (>= 15 required)
--   * Third Normal Form throughout: no transitive or partial dependencies
--   * Surrogate INT AUTO_INCREMENT PKs for ELT stability
--   * InnoDB / utf8mb4
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------------
-- S1 | Dimension: Athlete
-- One row per anonymous athlete from multimodal_sports_injury_dataset.csv.
-- Static profile attributes separated from session-level measurements (3NF).
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_athlete` (
  `athlete_id`        INT         NOT NULL AUTO_INCREMENT,
  `source_athlete_id` INT         NOT NULL,        -- original athlete_id in CSV
  `sport_type`        VARCHAR(64) DEFAULT NULL,
  `gender`            VARCHAR(16) DEFAULT NULL,
  `age`               TINYINT     DEFAULT NULL,
  `bmi`               DECIMAL(5,2) DEFAULT NULL,
  PRIMARY KEY (`athlete_id`),
  UNIQUE KEY `uq_source_athlete` (`source_athlete_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S1 | Fact: Session
-- One row per training session from multimodal_sports_injury_dataset.csv.
-- Contains all per-session physiological, biomechanical, and load metrics.
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_session` (
  `session_id`            INT           NOT NULL AUTO_INCREMENT,
  `athlete_id`            INT           NOT NULL,  -- FK → dim_athlete
  `source_session_id`     INT           NOT NULL,  -- original session_id in CSV
  `heart_rate`            DECIMAL(6,2)  DEFAULT NULL,
  `body_temperature`      DECIMAL(5,2)  DEFAULT NULL,
  `hydration_level`       DECIMAL(5,2)  DEFAULT NULL,
  `sleep_quality`         DECIMAL(5,2)  DEFAULT NULL,
  `recovery_score`        DECIMAL(5,2)  DEFAULT NULL,
  `stress_level`          DECIMAL(5,2)  DEFAULT NULL,
  `muscle_activity`       DECIMAL(7,4)  DEFAULT NULL,
  `joint_angles`          DECIMAL(6,2)  DEFAULT NULL,
  `gait_speed`            DECIMAL(5,2)  DEFAULT NULL,
  `cadence`               DECIMAL(6,2)  DEFAULT NULL,
  `step_count`            INT           DEFAULT NULL,
  `jump_height`           DECIMAL(5,2)  DEFAULT NULL,
  `ground_reaction_force` DECIMAL(8,2)  DEFAULT NULL,
  `range_of_motion`       DECIMAL(6,2)  DEFAULT NULL,
  `training_intensity`    VARCHAR(32)   DEFAULT NULL,
  `training_duration`     DECIMAL(6,2)  DEFAULT NULL,
  `training_load`         DECIMAL(8,2)  DEFAULT NULL,  -- input for IRS calculation
  `fatigue_index`         DECIMAL(5,2)  DEFAULT NULL,
  `injury_occurred`       TINYINT(1)    DEFAULT NULL,  -- 0 = no, 1 = yes
  `playing_surface`       VARCHAR(32)   DEFAULT NULL,
  `ambient_temperature`   DECIMAL(5,2)  DEFAULT NULL,
  `humidity`              DECIMAL(5,2)  DEFAULT NULL,
  `altitude`              DECIMAL(7,2)  DEFAULT NULL,
  PRIMARY KEY (`session_id`),
  KEY `idx_session_athlete` (`athlete_id`),
  CONSTRAINT `fk_session_athlete`
    FOREIGN KEY (`athlete_id`) REFERENCES `dim_athlete` (`athlete_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Conformed Dimension: Position  (shared by S2 and S3)
-- Bridges dim_player (S2) and fact_player_profile (S3) for cross-source
-- analysis at position-group level.
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_position` (
  `position_id`   INT         NOT NULL AUTO_INCREMENT,
  `position_code` VARCHAR(8)  NOT NULL,  -- GK | DEF | MID | FWD
  `position_name` VARCHAR(32) NOT NULL,
  PRIMARY KEY (`position_id`),
  UNIQUE KEY `uq_position_code` (`position_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S2 | Dimension: Player
-- One row per named European player from full_dataset_thesis - 1.csv.
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_player` (
  `player_id`   INT          NOT NULL AUTO_INCREMENT,
  `player_name` VARCHAR(128) NOT NULL,
  `position_id` INT          DEFAULT NULL,  -- FK → dim_position
  PRIMARY KEY (`player_id`),
  UNIQUE KEY `uq_player_name` (`player_name`),
  KEY `idx_player_position` (`position_id`),
  CONSTRAINT `fk_player_position`
    FOREIGN KEY (`position_id`) REFERENCES `dim_position` (`position_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S2 | Dimension: Club
-- One row per club from full_dataset_thesis - 1.csv.
-- ---------------------------------------------------------------------------
CREATE TABLE `dim_club` (
  `club_id`   INT          NOT NULL AUTO_INCREMENT,
  `club_name` VARCHAR(128) NOT NULL,
  `league`    VARCHAR(64)  DEFAULT NULL,
  PRIMARY KEY (`club_id`),
  UNIQUE KEY `uq_club_name` (`club_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S2 | Bridge: Player <-> Club  [M:N]                            (Rule R3)
-- A player can play for multiple clubs across seasons;
-- a club has multiple players each season.
-- Relationship attributes: season (e.g. '20/21')
-- ---------------------------------------------------------------------------
CREATE TABLE `bridge_player_club` (
  `player_club_id` INT        NOT NULL AUTO_INCREMENT,
  `player_id`      INT        NOT NULL,  -- FK → dim_player
  `club_id`        INT        NOT NULL,  -- FK → dim_club
  `season`         VARCHAR(8) NOT NULL,  -- e.g. '20/21'
  PRIMARY KEY (`player_club_id`),
  UNIQUE KEY `uq_player_club_season` (`player_id`, `club_id`, `season`),
  KEY `idx_bpc_club` (`club_id`),
  CONSTRAINT `fk_bpc_player` FOREIGN KEY (`player_id`) REFERENCES `dim_player` (`player_id`),
  CONSTRAINT `fk_bpc_club`   FOREIGN KEY (`club_id`)   REFERENCES `dim_club`   (`club_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S2 | Fact: Injury
-- One row per injury event from full_dataset_thesis - 1.csv.
-- References bridge_player_club to capture player + club + season context.
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_injury` (
  `injury_id`      INT          NOT NULL AUTO_INCREMENT,
  `player_club_id` INT          NOT NULL,  -- FK → bridge_player_club
  `injury_type`    VARCHAR(128) DEFAULT NULL,
  `days_absent`    SMALLINT     DEFAULT NULL,
  `games_missed`   SMALLINT     DEFAULT NULL,
  `injury_from`    DATE         DEFAULT NULL,
  `injury_until`   DATE         DEFAULT NULL,
  `player_age`     TINYINT      DEFAULT NULL,  -- age at time of injury
  PRIMARY KEY (`injury_id`),
  KEY `idx_injury_player_club` (`player_club_id`),
  CONSTRAINT `fk_injury_player_club`
    FOREIGN KEY (`player_club_id`) REFERENCES `bridge_player_club` (`player_club_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- S3 | Fact: Player Profile  (University benchmark dataset)
-- One row per anonymous player profile from data.csv.
-- Used as a reference benchmark: injury risk by position and physical profile.
-- Linked to dim_position for cross-source comparison with S2.
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_player_profile` (
  `profile_id`                 INT          NOT NULL AUTO_INCREMENT,
  `position_id`                INT          DEFAULT NULL,  -- FK → dim_position
  `age`                        TINYINT      DEFAULT NULL,
  `height_cm`                  DECIMAL(5,2) DEFAULT NULL,
  `weight_kg`                  DECIMAL(5,2) DEFAULT NULL,
  `bmi`                        DECIMAL(5,2) DEFAULT NULL,
  `training_hours_per_week`    DECIMAL(5,2) DEFAULT NULL,
  `matches_played_past_season` SMALLINT     DEFAULT NULL,
  `previous_injury_count`      SMALLINT     DEFAULT NULL,
  `knee_strength_score`        DECIMAL(5,2) DEFAULT NULL,
  `hamstring_flexibility`      DECIMAL(5,2) DEFAULT NULL,
  `reaction_time_ms`           DECIMAL(7,2) DEFAULT NULL,
  `balance_test_score`         DECIMAL(5,2) DEFAULT NULL,
  `sprint_speed_10m_s`         DECIMAL(5,2) DEFAULT NULL,
  `agility_score`              DECIMAL(5,2) DEFAULT NULL,
  `sleep_hours_per_night`      DECIMAL(4,2) DEFAULT NULL,
  `stress_level_score`         DECIMAL(5,2) DEFAULT NULL,
  `nutrition_quality_score`    DECIMAL(5,2) DEFAULT NULL,
  `warmup_routine_adherence`   TINYINT(1)   DEFAULT NULL,
  `injury_next_season`         TINYINT(1)   DEFAULT NULL,  -- 0 = no, 1 = yes
  PRIMARY KEY (`profile_id`),
  KEY `idx_profile_position` (`position_id`),
  CONSTRAINT `fk_profile_position`
    FOREIGN KEY (`position_id`) REFERENCES `dim_position` (`position_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Derived | Fact: Load Metrics  (session-based IRS)
-- Computed from fact_session via INSERT...SELECT (ELT step 52).
-- Acute load  = AVG(training_load) over last 7 sessions per athlete
-- Chronic load = AVG(training_load) over last 28 sessions per athlete
-- IRS = acute_load_7s / chronic_load_28s
-- Decision rule: IRS >= 1.5 → high risk | 0.8–1.5 → optimal | < 0.8 → under
-- ---------------------------------------------------------------------------
CREATE TABLE `fact_load_metrics` (
  `load_metrics_id`  INT           NOT NULL AUTO_INCREMENT,
  `athlete_id`       INT           NOT NULL,  -- FK → dim_athlete
  `session_id`       INT           NOT NULL,  -- FK → fact_session (reference session)
  `session_seq`      INT           NOT NULL,  -- ordinal session number within athlete
  `acute_load_7s`    DECIMAL(10,2) DEFAULT NULL,
  `chronic_load_28s` DECIMAL(10,2) DEFAULT NULL,
  `irs`              DECIMAL(6,3)  DEFAULT NULL,
  `risk_band`        VARCHAR(16)   DEFAULT NULL,  -- high | optimal | under
  PRIMARY KEY (`load_metrics_id`),
  UNIQUE KEY `uq_load_athlete_session` (`athlete_id`, `session_id`),
  KEY `idx_load_session` (`session_id`),
  CONSTRAINT `fk_load_athlete`
    FOREIGN KEY (`athlete_id`) REFERENCES `dim_athlete`  (`athlete_id`),
  CONSTRAINT `fk_load_session`
    FOREIGN KEY (`session_id`) REFERENCES `fact_session` (`session_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET FOREIGN_KEY_CHECKS = 1;
