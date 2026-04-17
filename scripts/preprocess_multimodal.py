"""
Preprocess Multimodal Sports Injury Dataset
- Clean column names and data types
- Generate synthetic dates (rank-based assignment across 2024-08-01 to 2025-05-31)
- Map athlete_id to University players (rank-based deterministic mapping)
- Output staging CSV for SQL load
"""

import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime, timedelta

# Load datasets
raw_multi_path = Path(__file__).parent.parent / "data" / "raw" / "multimodal" / "multimodal_sports_injury_dataset.csv"
processed_multi_path = Path(__file__).parent.parent / "data" / "processed" / "multimodal_cleaned.csv"
processed_map_path = Path(__file__).parent.parent / "data" / "processed" / "multimodal_university_mapping.csv"
processed_univ_path = Path(__file__).parent.parent / "data" / "processed" / "university_cleaned.csv"

print(f"Loading Multimodal from {raw_multi_path}...")
df_multi = pd.read_csv(raw_multi_path)

print(f"Loading University players from {processed_univ_path}...")
df_univ = pd.read_csv(processed_univ_path)

print(f"Multimodal shape: {df_multi.shape}")
print(f"University shape: {df_univ.shape}")

# Standardize column names
df_multi.columns = df_multi.columns.str.lower().str.replace(" ", "_")

# --- DATE GENERATION ---
# Assign synthetic dates to sessions based on athlete workload distribution
# Period: 2024-08-01 to 2025-05-31 (~275 days)
start_date = datetime(2024, 8, 1)
end_date = datetime(2025, 5, 31)
num_days = (end_date - start_date).days + 1

# Group by athlete, count sessions per athlete
athlete_session_counts = df_multi.groupby('athlete_id').size().reset_index(name='session_count')

# Assign sessions to dates deterministically:
# Each athlete gets sessions spread over the period
# For simplicity: assign session_i from athlete_a to date based on (athlete_id, session_rank_within_athlete)

session_dates = []
current_date = start_date

for _, row in df_multi.iterrows():
    # Assign date sequentially across the entire dataset
    # This spreads sessions evenly across athletes and dates
    days_offset = len(session_dates) % num_days
    assigned_date = start_date + timedelta(days=days_offset)
    session_dates.append(assigned_date)

df_multi['session_date'] = session_dates

print(f"Assigned dates from {df_multi['session_date'].min()} to {df_multi['session_date'].max()}")

# --- RANK-BASED MAPPING: Multimodal athlete_id -> University player_id ---
# Rank Multimodal athletes by session count (DESC)
athlete_ranking = athlete_session_counts.sort_values('session_count', ascending=False).reset_index(drop=True)
athlete_ranking['multimodal_rank'] = range(1, len(athlete_ranking) + 1)

# Rank University players by prior injuries (DESC) then name (ASC)
df_univ_ranked = df_univ.copy()
df_univ_ranked = df_univ_ranked.sort_values(
    by=['previous_injury_count', 'age'],
    ascending=[False, True]
).reset_index(drop=True)
df_univ_ranked['university_rank'] = range(1, len(df_univ_ranked) + 1)

# Match by rank: athlete with most sessions -> player with most prior injuries
mapping = []
for idx, (_, multi_row) in enumerate(athlete_ranking.iterrows()):
    athlete_id = multi_row['athlete_id']
    multi_rank = multi_row['multimodal_rank']

    # Get corresponding University player (or None if beyond dataset size)
    if multi_rank <= len(df_univ_ranked):
        univ_player_id = df_univ_ranked.iloc[multi_rank - 1]['university_player_id']
        univ_age = df_univ_ranked.iloc[multi_rank - 1]['age']
    else:
        univ_player_id = None
        univ_age = None

    mapping.append({
        'athlete_id': int(athlete_id),
        'multimodal_rank': multi_rank,
        'session_count': multi_row['session_count'],
        'university_player_id': univ_player_id,
        'university_rank': multi_rank if univ_player_id else None,
        'university_age': univ_age
    })

df_mapping = pd.DataFrame(mapping)

# Add mapped player_id to multimodal data
athlete_to_player = dict(zip(df_mapping['athlete_id'], df_mapping['university_player_id']))
df_multi['player_id'] = df_multi['athlete_id'].map(athlete_to_player)

# Filter to only mapped athletes (those with a University match)
df_multi_mapped = df_multi[df_multi['player_id'].notna()].copy()

print(f"\nRank-based mapping results:")
print(f"  Multimodal athletes: {len(athlete_ranking)}")
print(f"  University players: {len(df_univ_ranked)}")
print(f"  Mapped athletes: {df_multi_mapped['athlete_id'].nunique()}")
print(f"  Total sessions (mapped): {len(df_multi_mapped)}")

# --- CLEAN AND SELECT COLUMNS ---
# Map Multimodal columns to fact_training_session schema
df_clean = df_multi_mapped[[
    'player_id', 'session_id', 'session_date', 'sport_type', 'gender', 'age',
    'training_intensity', 'training_duration', 'training_load', 'fatigue_index',
    'heart_rate', 'recovery_score', 'stress_level',
    'gait_speed', 'cadence', 'step_count', 'jump_height',
    'ground_reaction_force', 'range_of_motion',
    'injury_occurred'
]].copy()

# Rename columns to match staging table
df_clean.rename(columns={
    'player_id': 'university_player_id',
    'session_date': 'training_date',
    'training_intensity': 'rpe',  # Proxy
    'training_duration': 'duration_min',
    'training_load': 'daily_load',
    'gait_speed': 'speed_m_s',
    'ground_reaction_force': 'grf',
    'range_of_motion': 'rom_degrees',
    'injury_occurred': 'injury_observed'
}, inplace=True)

# Ensure numeric types
numeric_cols = ['rpe', 'duration_min', 'daily_load', 'fatigue_index', 'heart_rate']
for col in numeric_cols:
    if col in df_clean.columns:
        df_clean[col] = pd.to_numeric(df_clean[col], errors='coerce')

# Save outputs
processed_multi_path.parent.mkdir(parents=True, exist_ok=True)
df_clean.to_csv(processed_multi_path, index=False, encoding='utf-8')
df_mapping.to_csv(processed_map_path, index=False, encoding='utf-8')

print(f"\nSaved Multimodal cleaned to {processed_multi_path}")
print(f"Saved mapping to {processed_map_path}")
print(f"\nMultimodal cleaned head:\n{df_clean.head()}")
print(f"\nMapping head:\n{df_mapping.head()}")
