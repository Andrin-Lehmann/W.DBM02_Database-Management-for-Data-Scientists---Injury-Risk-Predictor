from pathlib import Path

import mysql.connector


def load_env(path=".env"):
    env = {}
    env_path = Path(path)
    if not env_path.exists():
        raise FileNotFoundError("Missing .env file with MySQL connection variables.")

    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def connect():
    env = load_env()
    return mysql.connector.connect(
        host=env["MYSQL_HOST"],
        port=int(env.get("MYSQL_PORT", "3306")),
        user=env["MYSQL_USER"],
        password=env["MYSQL_PASSWORD"],
        database=env["MYSQL_DATABASE"],
        connection_timeout=15,
    )


def print_rows(cur, query, formatter):
    cur.execute(query)
    for row in cur.fetchall():
        print(formatter(row))


conn = connect()
cur = conn.cursor()

print("## ROW COUNTS")
print_rows(
    cur,
    """
    SELECT 'stg_european_injuries' AS t, COUNT(*) FROM stg_european_injuries UNION ALL
    SELECT 'stg_multimodal_sessions', COUNT(*) FROM stg_multimodal_sessions UNION ALL
    SELECT 'stg_university_benchmark', COUNT(*) FROM stg_university_benchmark UNION ALL
    SELECT 'dim_age_group', COUNT(*) FROM dim_age_group UNION ALL
    SELECT 'dim_position_group', COUNT(*) FROM dim_position_group UNION ALL
    SELECT 'dim_team', COUNT(*) FROM dim_team UNION ALL
    SELECT 'dim_date', COUNT(*) FROM dim_date UNION ALL
    SELECT 'dim_player_european', COUNT(*) FROM dim_player_european UNION ALL
    SELECT 'bridge_player_team', COUNT(*) FROM bridge_player_team UNION ALL
    SELECT 'dim_athlete_multimodal', COUNT(*) FROM dim_athlete_multimodal UNION ALL
    SELECT 'fact_university_benchmark', COUNT(*) FROM fact_university_benchmark UNION ALL
    SELECT 'fact_injury_european', COUNT(*) FROM fact_injury_european UNION ALL
    SELECT 'fact_training_session', COUNT(*) FROM fact_training_session UNION ALL
    SELECT 'fact_load_metrics', COUNT(*) FROM fact_load_metrics
    """,
    lambda r: f"  {r[0]}: {r[1]}",
)

print("\n## IRS RISK BAND DISTRIBUTION (raw)")
print_rows(
    cur,
    "SELECT risk_band, COUNT(*) AS cnt FROM fact_load_metrics GROUP BY risk_band ORDER BY cnt DESC",
    lambda r: f"  {r[0]}: {r[1]}",
)

print("\n## ADJUSTED IRS BAND DISTRIBUTION")
print_rows(
    cur,
    """
    SELECT adjusted_risk_band, COUNT(*) AS cnt
    FROM vw_adjusted_irs_by_age_group
    WHERE adjusted_irs IS NOT NULL
    GROUP BY adjusted_risk_band
    ORDER BY cnt DESC
    """,
    lambda r: f"  {r[0]}: {r[1]}",
)

print("\n## SAMPLE ADJUSTED IRS (top 10)")
print_rows(
    cur,
    """
    SELECT mm_athlete_id, age_group_label, full_date, ROUND(irs,3),
           ROUND(prior_injury_multiplier,3), ROUND(position_age_factor,3),
           ROUND(adjusted_irs,3), adjusted_risk_band
    FROM vw_adjusted_irs_by_age_group
    WHERE adjusted_irs IS NOT NULL
    ORDER BY adjusted_irs DESC
    LIMIT 10
    """,
    lambda r: f"  {r}",
)

print("\n## DATE RANGE in dim_date")
cur.execute("SELECT MIN(full_date), MAX(full_date), COUNT(*) FROM dim_date")
row = cur.fetchone()
print(f"  {row[0]} to {row[1]} ({row[2]} distinct dates)")

print("\n## INJURY TYPES top 10")
print_rows(
    cur,
    "SELECT injury_name, COUNT(*) AS cnt FROM fact_injury_european GROUP BY injury_name ORDER BY cnt DESC LIMIT 10",
    lambda r: f"  {r[0]}: {r[1]}",
)

print("\n## AGE GROUP DISTRIBUTION (multimodal athletes)")
print_rows(
    cur,
    """
    SELECT ag.age_group_label, COUNT(*) AS cnt
    FROM dim_athlete_multimodal a
    JOIN dim_age_group ag ON ag.age_group_id = a.age_group_id
    GROUP BY ag.age_group_label
    ORDER BY MIN(ag.min_age)
    """,
    lambda r: f"  {r[0]}: {r[1]}",
)

print("\n## SEASONS in bridge_player_team")
print_rows(
    cur,
    "SELECT season, COUNT(*) AS cnt FROM bridge_player_team GROUP BY season ORDER BY season",
    lambda r: f"  {r[0]}: {r[1]}",
)

cur.close()
conn.close()
