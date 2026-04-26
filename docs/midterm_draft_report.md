# Midterm Draft Report

This document is a lightweight draft/status snapshot for the DBM midterm. The final submission report remains `injury_risk_report.qmd`.

## Project Idea

The Injury Risk Predictor supports a football coach in identifying athletes whose recent workload pattern suggests elevated injury risk. The database combines workload sessions, European injury-event records, and static player benchmark data.

## Data Integration Strategy

The three source datasets do not share a universal player identifier. The schema therefore uses a hybrid integration strategy:

- Multimodal source: anonymous athlete workload sessions and IRS calculation.
- European injuries source: football player names, clubs, seasons, and injury events.
- University source: anonymous static benchmark profiles.

Cross-source analysis is intentionally limited to aggregate dimensions such as age group and position group. No claim is made that rows from all three datasets represent the same real-world player.

## Current Database Shape

Main dimensions:

- `dim_age_group`
- `dim_position_group`
- `dim_date`
- `dim_athlete_multimodal`
- `dim_team`
- `dim_player_european`
- `bridge_player_team`

Main facts:

- `fact_training_session`
- `fact_load_metrics`
- `fact_injury_european`
- `fact_university_benchmark`

Analytics view:

- `vw_adjusted_irs_by_age_group`

## Implemented Decision Rule

The implemented SQL bands are:

| Band | Range | Interpretation |
|---|---:|---|
| High Risk | `IRS >= 2.0` | immediate load reduction |
| Caution | `1.2 <= IRS < 2.0` | monitor closely |
| Optimal | `0.8 <= IRS < 1.2` | maintain training plan |
| Underloaded | `IRS < 0.8` | progressively increase load |
| Not enough history | fewer than 28 sessions | wait for chronic window |

The `2.0` high-risk threshold is used for the implemented and adjusted score because benchmark multipliers inflate values above the raw IRS range.

## Reproducibility Status

The intended execution order is:

1. `sql/01_schema/00_initialize_db.sql`
2. `sql/01_schema/01_create_tables.sql`
3. `sql/02_load/20_load_staging.sql`
4. `sql/03_transform/30_transform_dims_facts.sql`
5. `sql/05_optimization/51_create_indexes.sql`
6. `sql/04_analytics/40_irs_rolling_window.sql`

`sql/05_optimization/52_materialized_irs.sql` can be used to rebuild `fact_load_metrics` independently.

## Known Limitations

- Multimodal dates are synthetic because the source has session order but no calendar date.
- Player-level joins across all three datasets are not methodologically defensible.
- The European source represents professional football, while the University benchmark source likely represents a different population.
- The final report still needs screenshots and final performance evidence.
