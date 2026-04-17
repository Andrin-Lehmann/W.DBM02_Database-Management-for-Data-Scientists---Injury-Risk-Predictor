# Injury Risk Predictor

**Module:** Database Management for Data Scientists (DBM) — HSLU, MSc Applied Information and Data Science
**Stack:** MySQL 8 · Metabase · Quarto (PDF report)
**Team:** TBD

---

## 1 · Use case in one sentence

A football coach uses an interactive dashboard to identify players whose **Injury Risk Score (IRS)** — the acute-to-chronic workload ratio — is in the danger zone, so training load can be reduced before an injury occurs.

## 2 · Decision rule

| IRS band | Meaning | Coach action |
|---|---|---|
| IRS ≥ 1.5 | High risk (sweet spot exceeded) | Reduce load / rest player |
| 0.8 ≤ IRS < 1.5 | Optimal training zone | Maintain plan |
| IRS < 0.8 | Undertraining | Progressively increase load |

Thresholds follow Gabbett's acute:chronic workload ratio framework (British Journal of Sports Medicine, 2016).

## 3 · Data sources

| # | Dataset | Role in schema | Granularity |
|---|---|---|---|
| A | Multimodal Sports Injury Dataset | Workload & biomechanical time series | Session × player |
| B | European Football Injuries 2020–2025 | Injury events across leagues | Injury incident |
| C | University Football Injury Prediction Dataset (~800 players) | Player features + injury labels | Player (static) |

Datasets are independent in form (time-series vs. event log vs. tabular features) and content (load telemetry vs. league injury records vs. anthropometric profiles). The join key strategy is documented in `docs/data_integration.md`.

## 4 · Repository layout

```
injury-risk-predictor/
├── README.md                          ← this file
├── injury_risk_report.qmd             ← main Quarto report (the deliverable)
├── _quarto.yml                        ← Quarto project config
├── requirements.txt                   ← Python deps for preprocessing scripts
├── .gitignore
│
├── data/
│   ├── raw/                           ← original downloads, unchanged (gitignored if large)
│   │   ├── multimodal/
│   │   ├── european_injuries/
│   │   └── university/
│   └── processed/                     ← CSVs ready for MySQL LOAD DATA (UTF-8, comma-delimited)
│
├── sql/
│   ├── 01_schema/
│   │   └── 01_create_tables.sql       ← DDL: all CREATE TABLE statements, 3NF
│   ├── 02_load/                       ← LOAD DATA INFILE into staging tables
│   │   ├── 10_load_staging_multimodal.sql
│   │   ├── 11_load_staging_european.sql
│   │   └── 12_load_staging_university.sql
│   ├── 03_transform/                  ← ELT: INSERT ... SELECT into target schema
│   │   ├── 20_insert_dim_team.sql
│   │   ├── 21_insert_dim_position.sql
│   │   ├── 22_insert_dim_player.sql
│   │   ├── 23_insert_dim_date.sql
│   │   ├── 24_insert_fact_training_session.sql
│   │   ├── 25_insert_fact_match.sql
│   │   ├── 26_insert_fact_injury.sql
│   │   └── 27_insert_fact_load_metrics.sql
│   ├── 04_analytics/
│   │   ├── 40_irs_rolling_window.sql  ← the main KPI query (window fn + CTE)
│   │   ├── 41_irs_decision_bands.sql  ← CASE WHEN mapping to risk bands
│   │   └── 42_injury_rate_by_band.sql ← validation query
│   └── 05_optimization/
│       ├── 50_baseline_explain.sql    ← EXPLAIN ANALYZE before indexing
│       ├── 51_create_indexes.sql      ← B-tree indexes on (player_id, date)
│       ├── 52_materialized_irs.sql    ← precomputed IRS summary table
│       └── 53_explain_after.sql       ← EXPLAIN ANALYZE after optimization
│
├── Pictures/                          ← screenshots referenced in the .qmd
│   ├── er_diagram.png
│   ├── schema_ddl.png
│   ├── execution_plan_before.png
│   ├── execution_plan_after.png
│   ├── metabase_dashboard.png
│   └── metabase_risk_ranking.png
│
├── metabase/
│   ├── dashboard_export.json          ← serialized dashboard for reproducibility
│   └── connection_setup.md            ← how to connect Metabase to MySQL
│
├── scripts/
│   ├── preprocess_multimodal.py       ← minimal preprocessing (encoding, column naming)
│   ├── preprocess_european.py
│   └── preprocess_university.py
│
└── docs/
    ├── data_integration.md            ← how the 3 datasets are joined
    ├── setup_mysql.md                 ← VM + MySQL install notes
    └── setup_metabase.md              ← Metabase install + datasource config
```

## 5 · How to reproduce

1. **Install MySQL 8** on the HSLU Lab Services VM (see `docs/setup_mysql.md`).
2. **Place raw data** in `data/raw/` (Kaggle download URLs in `docs/data_integration.md`).
3. **Run preprocessing**: `python scripts/preprocess_*.py` → writes cleaned CSVs to `data/processed/`.
4. **Execute SQL scripts in order**: `01_schema` → `02_load` → `03_transform` → `04_analytics` → `05_optimization`.
5. **Start Metabase**, connect to MySQL, import `metabase/dashboard_export.json`.
6. **Render the report**: `quarto render injury_risk_report.qmd`.

## 6 · Submission access (to be filled before ILIAS deadline)

| Component | URL | User | Password |
|---|---|---|---|
| VM | `tbd` | `tbd` | `tbd` |
| MySQL | `tbd:3306` | `tbd` | `tbd` |
| Metabase | `http://tbd:3000` | `tbd` | `tbd` |

## 7 · Team

| Name | Email | Role |
|---|---|---|
| Andrin Kohler | andrin.kohler@stud.hslu.ch | Data modeling & ELT |
| TBD | — | — |
| TBD | — | — |
| TBD | — | — |
