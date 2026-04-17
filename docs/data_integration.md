# Dataset Integration Strategy

The three source datasets do not share a universal player ID. This document
specifies how they are bridged so that `dim_player` remains canonical.

## Source overview

| Dataset | Granularity | Join key candidates |
|---|---|---|
| University Football Injury (A) | Player (static, ~800 rows) | `player_name`, `team`, `position` |
| Multimodal Sports Injury (B) | Session × player (time-series) | anonymous `player_id`, `date` |
| European Football Injuries (C) | Injury event | `player_name`, `club`, `date_of_injury` |

## Integration approach

We use the **University dataset as the canonical player universe**. It has
clean player identifiers, static features, and a binary injury label — exactly
the attributes a `dim_player` table needs.

The other two are bridged as follows:

### (A) University ↔ (B) Multimodal

The Multimodal dataset uses anonymous numeric player IDs. Since name-matching
is impossible, we allocate a deterministic mapping:

1. Rank Multimodal players by total observed sessions (proxy for seniority).
2. Rank University players by `prior_injuries` descending, then name alphabetical.
3. Match by rank, truncated to the smaller of the two sets.

This mapping is stored in a staging table `map_multimodal_to_university` so
the join is explicit and auditable.

> **Alternative (production):** if a real club provided both feeds, players
> would match by license number. The synthetic mapping here is justified in
> the report's *Limitations* section.

### (A) University ↔ (C) European

Direct fuzzy name match using MySQL's `SOUNDEX` or a pre-computed
Levenshtein score in Python (see `scripts/preprocess_european.py`). Matches
with distance ≤ 2 are accepted. Unmatched European injuries are retained
at a **position × age-group benchmark level** (not attached to a specific
player) to support the league-level comparison cards in the dashboard.

## What each dataset contributes

| Table | Source |
|---|---|
| `dim_player` | A (enriched with C where matched) |
| `dim_team` | A, C |
| `dim_position` | A |
| `fact_training_session` | B (mapped via `map_multimodal_to_university`) |
| `bridge_appearance` + `fact_match` | synthetic (generated from B + C schedule) OR dropped if time-constrained |
| `fact_injury` | A (label) + C (events) — dedup on `(player_id, date_id, body_region)` |
| `fact_load_metrics` | derived from `fact_training_session` by `52_materialized_irs.sql` |

## Known limitations to disclose in the report

1. The Multimodal↔University bridge is rank-based, not identity-based.
2. The European injury records predominantly cover top-5-league pros, while
   the University dataset is college-level — the two populations differ, so
   cross-population claims are framed as *benchmarking* rather than
   equivalence.
3. Match appearances may be partially synthetic depending on what `fact_match`
   is populated from.

All three limitations are acceptable for a proof-of-concept database project;
they would need to be resolved before any production deployment.
