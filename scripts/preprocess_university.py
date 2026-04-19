"""
Preprocess University Football Injury Prediction Dataset
- Clean column names
- Handle missing values
- Ensure data types
- Output to data/processed/university_cleaned.csv
"""

import pandas as pd
import numpy as np
from pathlib import Path

# Load raw data
raw_path = Path(__file__).parent.parent / "data" / "raw" / "university" / "data.csv"
processed_path = Path(__file__).parent.parent / "data" / "processed" / "university_cleaned.csv"

print(f"Loading {raw_path}...")
df = pd.read_csv(raw_path)

print(f"Original shape: {df.shape}")
print(f"Columns: {list(df.columns)}")

# Standardize column names: Title_Case -> snake_case
df.columns = df.columns.str.lower().str.replace(" ", "_").str.replace("-", "_")

# Ensure correct data types
df['age'] = pd.to_numeric(df['age'], errors='coerce').fillna(0).astype(int)
df['height_cm'] = pd.to_numeric(df['height_cm'], errors='coerce').fillna(0).astype(int)
df['weight_kg'] = pd.to_numeric(df['weight_kg'], errors='coerce').fillna(0).astype(int)
df['position'] = df['position'].astype(str).str.strip()

# Normalize position codes to standard 4-level system: GK, DEF, MID, FWD
position_map = {
    'Goalkeeper': 'GK',
    'Defender': 'DEF',
    'Midfielder': 'MID',
    'Forward': 'FWD',
    'goalkeeper': 'GK',
    'defender': 'DEF',
    'midfielder': 'MID',
    'forward': 'FWD',
}
df['position'] = df['position'].map(position_map).fillna(df['position'])

# Cast numeric columns
numeric_cols = [
    'training_hours_per_week', 'matches_played_past_season',
    'previous_injury_count', 'knee_strength_score', 'hamstring_flexibility',
    'reaction_time_ms', 'balance_test_score', 'sprint_speed_10m_s',
    'agility_score', 'sleep_hours_per_night', 'stress_level_score',
    'nutrition_quality_score', 'warmup_routine_adherence',
    'injury_next_season', 'bmi'
]
for col in numeric_cols:
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors='coerce')

# Drop rows with critical missing values
df = df.dropna(subset=['age', 'height_cm', 'weight_kg', 'position'])

# Rename injury label for clarity
df.rename(columns={'injury_next_season': 'has_injury_label'}, inplace=True)

# Add surrogate player_id (row number, starting from 1)
df.insert(0, 'university_player_id', range(1, len(df) + 1))

print(f"Cleaned shape: {df.shape}")
print(f"Nulls:\n{df.isnull().sum()}")

# Save
processed_path.parent.mkdir(parents=True, exist_ok=True)
df.to_csv(processed_path, index=False, encoding='utf-8')
print(f"\nSaved to {processed_path}")
print(f"Head:\n{df.head()}")
