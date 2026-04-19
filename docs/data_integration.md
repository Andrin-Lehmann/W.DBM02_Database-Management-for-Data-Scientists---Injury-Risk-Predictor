# Dataset Integration Strategy

The three source datasets do not share a universal player ID. In addition, the
available CSV files do not support a real player-level merge across all three
sources: the Multimodal dataset has no player names or calendar dates, and the
University dataset has no player names, team names, or shared identifiers.
Therefore, the target database uses a **hybrid integration strategy** instead
of forcing one canonical `dim_player` across all sources.

## Source overview

| Dataset | Granularity | Identity fields actually available | Time fields actually available |
|---|---|---|---|
| University Football Injury (A) | Player (static, ~800 rows) | none beyond row-level profile | none |
| Multimodal Sports Injury (B) | Session × athlete | anonymous `athlete_id` | ordered `session_id`, but no real date |
| European Football Injuries (C) | Injury event | `player_name`, `club` | `injury_from_parsed`, `injury_until_parsed` |

## Integration approach

Because no universal player identifier exists, the project separates the data
into three source-specific subject areas and integrates them only where this is
methodologically defensible.

### 1. Multimodal athlete universe

The Multimodal dataset forms the **workload and IRS layer** of the project.

It is used to populate:

- `dim_athlete_multimodal`
- `fact_training_session`
- `fact_load_metrics`

`athlete_id` is treated as the local identifier for this source only. Since the
dataset does not contain explicit calendar dates, workload history is modeled
using the observed order of `session_id` within each athlete. For database
implementation, `session_id` may optionally be mapped to a **synthetic date**
so that a standard `dim_date` can still be used in the schema.

### 2. European football player universe

The European dataset forms the **football identity and injury-event layer** of
the project.

It is used to populate:

- `dim_team`
- `dim_player_european`
- `fact_injury_european`
- `dim_date`

This is the only source with real football player names, clubs, and injury
dates. Therefore, it is the appropriate source for football-specific player and
injury entities in the target database.

### 3. University benchmark universe

The University dataset forms the **static benchmark layer** of the project.

It is used to populate:

- `fact_university_benchmark`

This dataset contains useful static attributes such as age, position, previous
injury count, training hours, and injury-next-season label. However, it does
not contain player names, team names, or dates. For this reason, it is not used
as a canonical player master, but rather as a benchmark dataset for comparison
cards and aggregate summaries.

## Conformed dimensions

Although the three datasets cannot be joined at player level, they can still be
related through shared analytical dimensions at a coarser grain.

### Age groups

A shared `dim_age_group` is used to standardize age across sources.

Examples:
- 18–20
- 21–24
- 25–29
- 30+

This dimension can be linked to:

- `dim_athlete_multimodal`
- `dim_player_european`
- `fact_university_benchmark`

### Position groups

A shared `dim_position_group` is used where position is available.

Examples:
- GK
- DEF
- MID
- FWD

This dimension can be linked to:

- `dim_player_european`
- `fact_university_benchmark`

The Multimodal dataset does not contain position, so position-based comparisons
cannot include the Multimodal source directly.

### Date dimension

A standard `dim_date` is used for:

- real injury dates from the European dataset
- optional synthetic session dates from the Multimodal dataset

This allows consistent SQL filtering and dashboard parameterization, while still
being transparent about the fact that Multimodal dates are constructed.

## What each dataset contributes

| Table | Source | Role |
|---|---|---|
| `dim_athlete_multimodal` | B | local athlete dimension for workload data |
| `fact_training_session` | B | session-level workload observations |
| `fact_load_metrics` | B | derived rolling acute/chronic load and IRS |
| `dim_team` | C | football club dimension |
| `dim_player_european` | C | football player dimension |
| `fact_injury_european` | C | football injury events |
| `dim_date` | C + synthetic from B | calendar dimension |
| `fact_university_benchmark` | A | static benchmark and comparison layer |
| `dim_age_group` | derived | conformed analytical dimension |
| `dim_position_group` | derived | conformed analytical dimension |

## Analytical consequences

This integration design implies that the project supports two levels of analysis:

### Source-specific player analysis

- IRS calculation from the Multimodal source
- injury event analysis from the European source
- static injury-risk profiling from the University source

### Cross-source benchmark analysis

Cross-source comparisons are only made at an aggregate level, for example by:

- age group
- position group
- sport type
- injury frequency band
- workload risk band

This means the dashboard supports **benchmarking and contextual comparison**, not
a single row-level longitudinal history of the same real-world player across all
three datasets.

## Known limitations to disclose in the report

1. The three datasets cannot be joined through a real shared player identifier.
2. The Multimodal dataset has no explicit calendar date, so rolling workload is
   operationalized using session order; any associated dates are synthetic.
3. The University dataset has no player names or team identifiers, so it can
   only be used as a benchmark source, not as a canonical player dimension.
4. The European dataset covers professional football, while the University
   dataset reflects a different population; cross-source claims must therefore
   be framed as benchmarking rather than equivalence.
5. Position-based cross-source comparison is only possible between the European
   and University datasets, because the Multimodal dataset has no position field.

These limitations are acceptable for a proof-of-concept DBM project, provided
they are clearly disclosed and the analysis claims remain aligned with the
actual granularity of the source data.