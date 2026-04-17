# Data Mapping Strategy

## Dataset Overview

| Dataset | Rows | Role | PK | Key Columns |
|---------|------|------|----|----|
| **Multimodal** | 15,420 | Training sessions | athlete_id, session_id | sport_type, age, gender, bmi, training_load, injury_occurred |
| **European** | 15,603 | Injury events | (implicit) | player_name, player_age, player_position, club, league, Injury, Days |
| **University** | 800 | Player master | (implicit) | Age, Height_cm, Weight_kg, Position, Previous_Injury_Count, Injury_Next_Season |

## Integration Logic

### Multimodal → University (Rank-Based Mapping)

**Problem:** Multimodal uses `athlete_id` (1..15420), University has no athlete IDs → deterministic mapping needed.

**Solution:** Rank-based deterministic assignment (auditable, reproducible):

1. **Rank Multimodal:** by session frequency (DESC)
   - athlete_id with most sessions → rank 1
   - Less frequent athletes → lower ranks
   - Assign University player by rank order

2. **Rank University:** by injury risk (DESC then alphabetical)
   - Players with more `Previous_Injury_Count` → rank 1
   - Ties broken by alphabetical name order
   - Match 1st Multimodal athlete → 1st University player, etc.

3. **Store mapping:** Create `map_multimodal_to_university` table
   - (athlete_id, university_player_id, rank, mapping_date, quality_score)
   - Allows tracing of mapping decisions in report

**Rationale:** 
- No shared identifier exists
- Rank-based approach is deterministic (reproducible)
- Mapping table is auditable for lessons-learned section

---

### European → University (Fuzzy Name Matching)

**Problem:** European uses `player_name` (string), University has no names → fuzzy matching.

**Solution:** Levenshtein distance matching in preprocessing:

1. **Preprocessing (Python):**
   - Normalize European player names (lowercase, strip whitespace, diacritics)
   - Compute Levenshtein distance from each European name to all University players
   - Match if distance ≤ 2 (typos, encoding errors)
   - If distance > 2 → mark as unmatched

2. **Unmatched handling:**
   - Retain as synthetic injury records at position × age-group level
   - Used for league benchmarking (dashboard: "injury rate by position")

3. **Store match scores:** Create `map_european_to_university` staging table
   - (european_player_name, university_player_id, levenshtein_distance, match_confidence)

---

## Schema Mapping

### Multimodal → fact_training_session
| Source | Target | Notes |
|--------|--------|-------|
| athlete_id | player_id (via map_multimodal_to_university) | FK lookup |
| session_id | session_id | Direct |
| training_intensity, training_duration, training_load | rpe, duration_min, (calculated) | RPE derived from training_intensity |
| (none) | date_id | Need to generate synthetic dates or parse from session_id |
| gait_speed, cadence, ... | hsr_distance_m, sprint_count, ... | Biomechanics mapped to available fact columns |

**Missing data issue:** Multimodal has no explicit date → synthetic date generation needed.
- Assumption: 15,420 sessions over 1 year (2024-08-01 to 2025-05-31) = ~6 sessions per day per athlete
- Distribute evenly or use session_id as proxy for time sequence

### European → fact_injury
| Source | Target | Notes |
|--------|--------|-------|
| player_name | player_id (via map_european_to_university) | FK lookup via fuzzy match |
| injury_from_parsed | date_id | Convert string date to FK |
| Injury | injury_type | Direct |
| injury_until_parsed - injury_from_parsed | absence_days | Calculated |
| Days | absence_days | Fallback if dates unavailable |
| player_position | (none) | Validation/match quality |
| club, league | (none) | For league benchmarking only |

### University → dim_player (Master)
| Source | Target | Notes |
|--------|--------|-------|
| (implicit row num) | player_id | Surrogate key |
| Age | date_of_birth | Reverse-calculate from age (approximate) |
| Height_cm | height_cm | Direct |
| Weight_kg | weight_kg | Direct |
| Position | position_id | FK to dim_position (GK/DEF/MID/FWD) |
| Previous_Injury_Count | prior_injuries | Direct |

---

## Outstanding Decisions

1. **Multimodal date generation:** How to assign realistic dates to 15,420 sessions?
   - Option A: Use session_id as ordinal (1..15420 → 2024-08-01 + offset)
   - Option B: Cluster by athlete_id, distribute sessions evenly per athlete
   - Option C: Load sessions with NULL date_id initially, backfill synthetically

2. **Synthetic European matches:** For unmatched injuries (distance > 2), do we:
   - Drop them entirely?
   - Retain as synthetic records without player_id FK (denormalized)?
   - Create synthetic players in dim_player?

3. **Multimodal session features:** Which columns map to fact_training_session's limited schema?
   - fact_training_session has: rpe, duration_min, total_distance_m, hsr_distance_m, sprint_count, etc.
   - Multimodal has: training_intensity, training_duration, training_load, gait_speed, cadence, jump_height, etc.
   - Mapping is lossy — need to document which fields are dropped.

---

## Implementation Sequence

1. **Preprocessing (Python):** Clean CSVs, compute fuzzy matches, generate synthetic dates → `data/processed/`
2. **Load (SQL):** LOAD DATA INFILE → staging tables
3. **Transform (SQL):**
   - Insert dim_team, dim_position, dim_date
   - Compute map_multimodal_to_university, map_european_to_university
   - Insert dim_player (with mapping)
   - Insert fact_training_session, fact_injury
4. **Materialize:** Refresh fact_load_metrics with IRS calculations
