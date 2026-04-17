"""
Preprocess European Football Injuries Dataset
- Clean column names and date parsing
- Normalize player names (strip accents, normalize casing)
- Fuzzy match to University players (Levenshtein distance)
- Output staging CSVs for SQL load
"""

import pandas as pd
import numpy as np
from pathlib import Path
from difflib import SequenceMatcher
import unicodedata
import re

def levenshtein_distance(s1, s2):
    """Compute Levenshtein distance between two strings."""
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)

    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]

def normalize_name(name):
    """Normalize player name: remove accents, lowercase, strip whitespace."""
    if not isinstance(name, str):
        return ""
    # Remove accents
    name = ''.join(c for c in unicodedata.normalize('NFD', name)
                   if unicodedata.category(c) != 'Mn')
    # Lowercase and strip
    return name.lower().strip()

# Load datasets
raw_euro_path = Path(__file__).parent.parent / "data" / "raw" / "european" / "full_dataset_thesis - 1.csv"
processed_euro_path = Path(__file__).parent.parent / "data" / "processed" / "european_cleaned.csv"
processed_matches_path = Path(__file__).parent.parent / "data" / "processed" / "european_university_matches.csv"
processed_univ_path = Path(__file__).parent.parent / "data" / "processed" / "university_cleaned.csv"

print(f"Loading European injuries from {raw_euro_path}...")
df_euro = pd.read_csv(raw_euro_path)

print(f"Loading University players from {processed_univ_path}...")
df_univ = pd.read_csv(processed_univ_path)

print(f"European shape: {df_euro.shape}")
print(f"University shape: {df_univ.shape}")

# Standardize European column names
df_euro.columns = df_euro.columns.str.lower().str.replace(" ", "_")

# Parse dates
df_euro['injury_from_parsed'] = pd.to_datetime(df_euro['injury_from_parsed'], format='%m/%d/%Y', errors='coerce')
df_euro['injury_until_parsed'] = pd.to_datetime(df_euro['injury_until_parsed'], format='%m/%d/%Y', errors='coerce')

# Extract days as numeric
df_euro['days_out'] = df_euro['injury_from_parsed'] - df_euro['injury_until_parsed']
df_euro['days_out'] = df_euro['days_out'].dt.days.abs().fillna(0).astype(int)

# Normalize player names
df_euro['player_name_normalized'] = df_euro['player_name'].apply(normalize_name)
df_univ['player_name_normalized'] = df_univ.get('player_name', '').apply(lambda x: normalize_name(x) if isinstance(x, str) else "")

# Fuzzy match: for each European player, find closest University player
matches = []
for idx, euro_row in df_euro.iterrows():
    euro_name = euro_row['player_name_normalized']
    euro_age = euro_row['player_age']

    best_distance = float('inf')
    best_match_id = None
    best_match_name = None

    # Find closest University player by name
    for _, univ_row in df_univ.iterrows():
        univ_name = univ_row.get('player_name_normalized', '')
        dist = levenshtein_distance(euro_name, univ_name)

        if dist < best_distance:
            best_distance = dist
            best_match_id = univ_row['university_player_id']
            best_match_name = univ_name

    # Only match if distance <= 2 (typos, encoding errors)
    match_type = 'matched' if best_distance <= 2 else 'unmatched'

    matches.append({
        'european_player_name': euro_row['player_name'],
        'european_player_name_normalized': euro_name,
        'european_player_age': euro_age,
        'university_player_id': best_match_id if best_distance <= 2 else None,
        'university_player_name_normalized': best_match_name if best_distance <= 2 else None,
        'levenshtein_distance': best_distance,
        'match_type': match_type
    })

df_matches = pd.DataFrame(matches)

# Filter European data for matched players only
df_euro['player_id'] = df_matches['university_player_id']
df_euro_matched = df_euro[df_euro['player_id'].notna()].copy()

print(f"\nFuzzy matching results:")
print(f"  Matched: {(df_matches['match_type'] == 'matched').sum()}")
print(f"  Unmatched: {(df_matches['match_type'] == 'unmatched').sum()}")

# Clean European for load
df_euro_clean = df_euro_matched[[
    'season', 'player_id', 'injury', 'days_out', 'games_missed',
    'injury_from_parsed', 'injury_until_parsed', 'player_age', 'player_position', 'club', 'league'
]].copy()

df_euro_clean.rename(columns={
    'season': 'league_season',
    'player_id': 'university_player_id',
    'injury': 'injury_type',
    'days_out': 'absence_days',
    'games_missed': 'games_missed',
    'injury_from_parsed': 'injury_date',
    'injury_until_parsed': 'recovery_date',
    'player_age': 'player_age_at_injury',
    'player_position': 'position',
    'club': 'club_name',
    'league': 'league_name'
}, inplace=True)

# Save outputs
processed_euro_path.parent.mkdir(parents=True, exist_ok=True)
df_euro_clean.to_csv(processed_euro_path, index=False, encoding='utf-8')
df_matches.to_csv(processed_matches_path, index=False, encoding='utf-8')

print(f"\nSaved European cleaned to {processed_euro_path}")
print(f"Saved matches to {processed_matches_path}")
print(f"\nEuropean cleaned head:\n{df_euro_clean.head()}")
print(f"\nMatches summary:\n{df_matches['match_type'].value_counts()}")
