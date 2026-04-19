# Injury Risk Predictor

**Module:** Database Management for Data Scientists (DBM) — HSLU, MSc Applied Information and Data Science  
**Stack:** MySQL 8 · Metabase · Quarto (PDF report)  
**Team:** TBD

---

## 1 · Use case in one sentence

A football coach uses an interactive dashboard to identify workload risk patterns and injury benchmarks so that training load can be adjusted before injury risk becomes critical.

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
| A | Multimodal Sports Injury Dataset | Workload, session metrics, IRS calculation | Session × athlete |
| B | European Football Injuries 2020–2025 | Football player, team, and injury-event layer | Injury event |
| C | University Football Injury Prediction Dataset (~800 players) | Static benchmark and profile layer | Player (static) |

The datasets are independent in form and content. Because they do not share a universal player ID, the project uses a hybrid integration strategy: source-specific player/athlete layers plus shared benchmark dimensions such as age group and position group. Details are documented in `docs/data_integration.md`.

## 4 · Repository layout

```text
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
│   │   └── 01_create_tables.sql
│   ├── 02_load/
│   │   ├── 10_load_staging_multimodal.sql
│   │   ├── 11_load_staging_european.sql
│   │   └── 12_load_staging_university.sql
│   ├── 03_transform/
│   │   ├── 20_insert_dim_team.sql
│   │   ├── 21_insert_dim_position_group.sql
│   │   ├── 22_insert_dim_player_european.sql
│   │   ├── 23_insert_dim_date.sql
│   │   ├── 24_insert_dim_athlete_multimodal.sql
│   │   ├── 25_insert_fact_training_session.sql
│   │   ├── 26_insert_fact_injury_european.sql
│   │   ├── 27_insert_fact_load_metrics.sql
│   │   └── 28_insert_fact_university_benchmark.sql
│   ├── 04_analytics/
│   │   ├── 40_irs_rolling_window.sql
│   │   ├── 41_irs_decision_bands.sql
│   │   └── 42_injury_rate_by_band.sql
│   └── 05_optimization/
│       ├── 50_baseline_explain.sql
│       ├── 51_create_indexes.sql
│       ├── 52_materialized_irs.sql
│       └── 53_explain_after.sql
│
├── Pictures/
│   ├── er_diagram.png
│   ├── schema_ddl.png
│   ├── execution_plan_before.png
│   ├── execution_plan_after.png
│   ├── metabase_dashboard.png
│   └── metabase_risk_ranking.png
│
├── metabase/
│   ├── dashboard_export.json
│   └── connection_setup.md
│
├── scripts/
│   ├── preprocess_multimodal.py
│   ├── preprocess_european.py
│   └── preprocess_university.py
│
└── docs/
    ├── data_integration.md
    ├── setup_mysql.md
    └── setup_metabase.md
````

## 5 · How to reproduce

1. **Install MySQL 8** on the HSLU Lab Services VM (see `docs/setup_mysql.md`).
2. **Place raw data** in `data/raw/` (download references in `docs/data_integration.md`).
3. **Run preprocessing**: `python scripts/preprocess_*.py` → writes cleaned CSVs to `data/processed/`.
4. **Execute SQL scripts in order**: `01_schema` → `02_load` → `03_transform` → `04_analytics` → `05_optimization`.
5. **Start Metabase**, connect to MySQL, and import `metabase/dashboard_export.json`.
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