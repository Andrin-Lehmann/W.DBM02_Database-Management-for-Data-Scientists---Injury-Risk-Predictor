"""Generate the ERD image used in the final report."""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Pictures" / "erd_injury_risk_predictor.png"

FIG_W, FIG_H = 20, 13.5
fig, ax = plt.subplots(figsize=(FIG_W, FIG_H))
ax.set_xlim(0, FIG_W)
ax.set_ylim(0, FIG_H)
ax.axis("off")
fig.patch.set_facecolor("white")

COLORS = {
    "dim": {"face": "#EEF2FF", "edge": "#6366F1"},
    "fact": {"face": "#F8FAFC", "edge": "#64748B"},
    "bridge": {"face": "#FFF7ED", "edge": "#EA580C"},
}
INTERNAL = "#94A3B8"
CONFORMED = "#10B981"
ENTITY_W, TITLE_H, ATTR_H, PAD = 2.45, 0.37, 0.27, 0.14


def entity_height(attrs):
    return TITLE_H + len(attrs) * ATTR_H + PAD


def draw_entity(cx, top, name, attrs, kind):
    h = entity_height(attrs)
    c = COLORS[kind]
    x0 = cx - ENTITY_W / 2
    y0 = top - h

    ax.add_patch(
        FancyBboxPatch(
            (x0 + 0.07, y0 - 0.07),
            ENTITY_W,
            h,
            boxstyle="round,pad=.06",
            fc="#E2E8F0",
            ec="none",
            zorder=3,
        )
    )
    ax.add_patch(
        FancyBboxPatch(
            (x0, y0),
            ENTITY_W,
            h,
            boxstyle="round,pad=.06",
            fc=c["face"],
            ec=c["edge"],
            lw=1.5,
            zorder=4,
        )
    )
    ax.add_patch(
        mpatches.Rectangle(
            (x0, top - TITLE_H),
            ENTITY_W,
            TITLE_H,
            fc=c["edge"],
            ec="none",
            alpha=0.20,
            zorder=5,
        )
    )
    ax.text(
        cx,
        top - TITLE_H / 2,
        name,
        ha="center",
        va="center",
        fontsize=7.6,
        fontweight="bold",
        color="#0F172A",
        zorder=6,
    )

    for i, attr in enumerate(attrs):
        y_attr = top - TITLE_H - 0.07 - i * ATTR_H - ATTR_H / 2
        prefix = attr[:3] if attr[:3] in ("PK ", "FK ", "UK ") else ""
        text = attr[3:] if prefix else attr
        prefix_color = {
            "PK ": "#B45309",
            "FK ": "#6B7280",
            "UK ": "#3B82F6",
        }.get(prefix, "#374151")
        if prefix:
            ax.text(
                x0 + 0.13,
                y_attr,
                prefix.strip(),
                ha="left",
                va="center",
                fontsize=5.9,
                color=prefix_color,
                fontweight="bold",
                zorder=6,
            )
        ax.text(
            x0 + 0.43,
            y_attr,
            text,
            ha="left",
            va="center",
            fontsize=6.4,
            color="#374151",
            zorder=6,
        )

    mid_y = (top + y0) / 2
    return {
        "top": (cx, top),
        "bot": (cx, y0),
        "lft": (x0, mid_y),
        "rgt": (x0 + ENTITY_W, mid_y),
        "cx": cx,
        "top_y": top,
        "bot_y": y0,
    }


def draw_group(x0, y0, x1, y1, label, color):
    ax.add_patch(
        FancyBboxPatch(
            (x0, y0),
            x1 - x0,
            y1 - y0,
            boxstyle="round,pad=.12",
            fc=color,
            ec="#CBD5E1",
            lw=1.5,
            zorder=1,
        )
    )
    ax.text(
        (x0 + x1) / 2,
        y1 - 0.27,
        label,
        ha="center",
        va="center",
        fontsize=9.5,
        fontweight="bold",
        color="#1E293B",
        zorder=2,
    )


def arrow(p0, p1, color=INTERNAL, conn="arc3,rad=0.0", zorder=3):
    ax.annotate(
        "",
        xy=p1,
        xytext=p0,
        arrowprops=dict(
            arrowstyle="-|>",
            color=color,
            lw=1.1,
            connectionstyle=conn,
        ),
        zorder=zorder,
    )


draw_group(0.15, 1.8, 5.7, 13.1, "S1  Multimodal workload", "#F0FDF4")
draw_group(5.9, 0.2, 10.6, 13.1, "Shared dimensions + S3", "#F9FAFB")
draw_group(10.8, 1.8, 19.7, 13.1, "S2  European injuries", "#EFF6FF")

ax.text(
    8.25,
    5.35,
    "S3  University benchmark",
    ha="center",
    va="center",
    fontsize=8,
    fontweight="bold",
    color="#7C3AED",
    zorder=2,
    bbox=dict(fc="#FAF5FF", ec="#A78BFA", boxstyle="round,pad=0.25", lw=1.0),
)

# S1
athlete = draw_entity(
    2.9,
    12.6,
    "dim_athlete_multimodal",
    [
        "PK mm_athlete_id",
        "UK source_id",
        "FK age_group_id",
        "gender",
        "sport_type",
        "bmi",
    ],
    "dim",
)
training = draw_entity(
    1.55,
    9.4,
    "fact_training_session",
    [
        "PK training_session_id",
        "FK mm_athlete_id",
        "FK date_id",
        "training_load",
        "training_intensity",
    ],
    "fact",
)
load_metrics = draw_entity(
    4.25,
    9.4,
    "fact_load_metrics",
    ["PK load_metrics_id", "FK mm_athlete_id", "FK date_id", "irs", "risk_band"],
    "fact",
)

# Shared dimensions
cx = 8.25
age_group = draw_entity(
    cx,
    12.6,
    "dim_age_group",
    ["PK age_group_id", "UK age_group_label", "min_age", "max_age"],
    "dim",
)
date = draw_entity(
    cx,
    10.05,
    "dim_date",
    ["PK date_id", "UK full_date", "year", "month"],
    "dim",
)
position_group = draw_entity(
    cx,
    7.65,
    "dim_position_group",
    ["PK position_group_id", "UK position_group_code", "position_group_name"],
    "dim",
)
benchmark = draw_entity(
    cx,
    5.1,
    "fact_university_benchmark",
    [
        "PK university_row_id",
        "FK age_group_id",
        "FK position_group_id",
        "previous_injury_count",
    ],
    "fact",
)

# S2
player = draw_entity(
    13.0,
    12.6,
    "dim_player_european",
    ["PK eu_player_id", "UK player_name", "FK age_group_id", "FK position_group_id"],
    "dim",
)
team = draw_entity(
    17.2,
    12.6,
    "dim_team",
    ["PK team_id", "UK team_name", "league", "country"],
    "dim",
)
bridge = draw_entity(
    15.1,
    9.4,
    "bridge_player_team",
    ["PK bridge_id", "FK eu_player_id", "FK team_id", "season"],
    "bridge",
)
injury = draw_entity(
    15.1,
    7.0,
    "fact_injury_european",
    ["PK injury_id", "FK bridge_id", "FK date_id", "injury_name", "days_absent"],
    "fact",
)

# Source-internal relationships.
arrow(athlete["bot"], training["top"], INTERNAL, "arc3,rad=-0.12")
arrow(athlete["bot"], load_metrics["top"], INTERNAL, "arc3,rad=0.12")
arrow(player["bot"], bridge["top"], INTERNAL, "arc3,rad=0.12")
arrow(team["bot"], bridge["top"], INTERNAL, "arc3,rad=-0.12")
arrow(bridge["bot"], injury["top"], INTERNAL)

# Shared dimension joins.
arrow(age_group["lft"], athlete["rgt"], CONFORMED)
arrow(date["lft"], training["rgt"], CONFORMED, "arc3,rad=-0.12")
arrow(date["lft"], load_metrics["rgt"], CONFORMED, "arc3,rad=0.15")
arrow(age_group["rgt"], player["lft"], CONFORMED)
arrow(position_group["rgt"], player["lft"], CONFORMED, "arc3,rad=0.20", zorder=2)
arrow(date["rgt"], injury["lft"], CONFORMED, "arc3,rad=-0.12")

# Route age_group to benchmark down the clear left margin of the shared column.
left_margin_x = 6.05
ax.plot(
    [age_group["lft"][0], left_margin_x],
    [age_group["lft"][1], age_group["lft"][1]],
    color=CONFORMED,
    lw=1.1,
    zorder=2,
    solid_capstyle="round",
)
ax.plot(
    [left_margin_x, left_margin_x],
    [age_group["lft"][1], benchmark["lft"][1]],
    color=CONFORMED,
    lw=1.1,
    zorder=2,
    solid_capstyle="round",
)
arrow((left_margin_x, benchmark["lft"][1]), benchmark["lft"], CONFORMED)
arrow(position_group["bot"], benchmark["top"], CONFORMED, zorder=2)

# Legend.
legend_y = 0.95
items = [
    ("Dimension", COLORS["dim"]["face"], COLORS["dim"]["edge"]),
    ("Fact", COLORS["fact"]["face"], COLORS["fact"]["edge"]),
    ("M:N bridge", COLORS["bridge"]["face"], COLORS["bridge"]["edge"]),
]
for i, (label, face, edge) in enumerate(items):
    box_x = 0.4 + i * 3.4
    ax.add_patch(
        FancyBboxPatch(
            (box_x, legend_y - 0.16),
            0.52,
            0.30,
            boxstyle="round,pad=.04",
            fc=face,
            ec=edge,
            lw=1.3,
            zorder=8,
        )
    )
    ax.text(
        box_x + 0.64,
        legend_y,
        label,
        va="center",
        fontsize=7.2,
        color="#334155",
        zorder=8,
    )

ax.annotate(
    "",
    xy=(11.1, legend_y),
    xytext=(10.2, legend_y),
    arrowprops=dict(arrowstyle="-|>", color=CONFORMED, lw=1.4),
    zorder=8,
)
ax.text(
    11.25,
    legend_y,
    "Conformed-dim join",
    va="center",
    fontsize=7.2,
    color="#334155",
    zorder=8,
)
ax.annotate(
    "",
    xy=(15.0, legend_y),
    xytext=(14.1, legend_y),
    arrowprops=dict(arrowstyle="-|>", color=INTERNAL, lw=1.4),
    zorder=8,
)
ax.text(
    15.15,
    legend_y,
    "1:N within source",
    va="center",
    fontsize=7.2,
    color="#334155",
    zorder=8,
)

ax.text(
    FIG_W / 2,
    0.38,
    "No universal player ID is assumed across datasets.  "
    "Cross-source comparisons use dim_age_group and dim_position_group only.",
    ha="center",
    va="center",
    fontsize=7,
    color="#475569",
    style="italic",
    bbox=dict(fc="#F1F5F9", ec="#CBD5E1", boxstyle="round,pad=.28", lw=.8),
    zorder=8,
)

plt.savefig(OUT, dpi=160, bbox_inches="tight", facecolor="white")
plt.close()
print(f"Saved: {OUT}")
