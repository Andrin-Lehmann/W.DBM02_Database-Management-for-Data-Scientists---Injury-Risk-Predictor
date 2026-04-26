# Injury Risk Predictor

**Module:** Database Management for Data Scientists (DBM), HSLU MSc Applied Information and Data Science  
**Stack:** MySQL 8/9, Metabase, Quarto  
**Deliverable:** `injury_risk_report.qmd`

## Use Case

A football coach uses an interactive dashboard to identify workload risk patterns and injury benchmarks so that training load can be adjusted before injury risk becomes critical.

## Decision Rule

The project uses an Injury Risk Score (IRS) based on the acute:chronic workload ratio. The implemented SQL bands are:

| IRS band | Range | Coach action |
|---|---:|---|
| High Risk | `IRS >= 2.0` | Reduce load immediately |
| Caution | `1.2 <= IRS < 2.0` | Monitor closely, reduce slightly |
| Optimal | `0.8 <= IRS < 1.2` | Maintain plan |
| Underloaded | `IRS < 0.8` | Progressively increase load |
| Not enough history | fewer than 28 sessions | Wait until chronic window is populated |

The raw ACWR/IRS logic follows Gabbett's workload framework. The upper high-risk threshold is set to `2.0` in the implemented dashboard because the adjusted score multiplies raw IRS by benchmark factors from the University and European injury datasets.

## Data Sources

| Dataset | Role in schema | Granularity |
|---|---|---|
| Multimodal Sports Injury Dataset | Workload, session metrics, IRS calculation | session x anonymous athlete |
| European Football Injuries 2020-2025 | Football player, team, and injury-event layer | injury event |
| University Football Injury Prediction Dataset | Static benchmark and profile layer | anonymous player profile |

The datasets do not share a universal player ID. The project therefore uses source-specific subject areas and joins only at defensible aggregate levels such as age group and position group. See `docs/data_integration.md`.

## Repository Layout

```text
injury-risk-predictor/
|-- README.md
|-- injury_risk_report.qmd
|-- _quarto.yml
|-- data/
|   |-- raw/
|   |   |-- data.csv
|   |   |-- full_dataset_thesis - 1.csv
|   |   |-- multimodal_sports_injury_dataset.csv
|   |   `-- raw_data.ipynb
|   `-- processed/
|-- docs/
|   |-- data_integration.md
|   |-- erd_injury_risk_predictor.mmd
|   `-- midterm_draft_report.qmd
|-- sql/
|   |-- 01_schema/
|   |   |-- 00_initialize_db.sql
|   |   `-- 01_create_tables.sql
|   |-- 02_load/
|   |   `-- 20_load_staging.sql
|   |-- 03_transform/
|   |   |-- 30_transform_dims_facts.sql
|   |   `-- 31_fix_load_metrics.sql
|   |-- 04_analytics/
|   |   `-- 40_irs_rolling_window.sql
|   `-- 05_optimization/
|       |-- 51_create_indexes.sql
|       `-- 52_materialized_irs.sql
`-- scripts/
    `-- report_data.py
```

## Reproduce the Database

1. Create the database:

   ```sql
   SOURCE sql/01_schema/00_initialize_db.sql;
   SOURCE sql/01_schema/01_create_tables.sql;
   ```

2. Load staging tables:

   ```sql
   SOURCE sql/02_load/20_load_staging.sql;
   ```

3. Transform staging data into dimensions, facts, and the adjusted IRS view:

   ```sql
   SOURCE sql/03_transform/30_transform_dims_facts.sql;
   ```

4. Rebuild load metrics independently if needed:

   ```sql
   SOURCE sql/05_optimization/52_materialized_irs.sql;
   ```

5. Add optimization indexes:

   ```sql
   SOURCE sql/05_optimization/51_create_indexes.sql;
   ```

6. Run the analytics query:

   ```sql
   SOURCE sql/04_analytics/40_irs_rolling_window.sql;
   ```

## Environment

Local credentials belong in `.env`, which is intentionally ignored by Git.

Expected variables:

```text
MYSQL_HOST=
MYSQL_PORT=
MYSQL_DATABASE=
MYSQL_USER=
MYSQL_PASSWORD=
```

The helper script `scripts/report_data.py` reads these values from `.env`; it should not contain credentials.

## Notes

- `data/raw/*.csv` is currently tracked because these small project datasets are part of the reproducible DBM hand-in.
- `.mcp.json` and local Codex/Claude bridge scripts are ignored because they are local tooling, not part of the database deliverable.
- `injury_risk_report.qmd` is the final report file. `docs/midterm_draft_report.qmd` is the midterm draft report.
