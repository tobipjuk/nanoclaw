---
name: whoop
description: Fetch Whoop recovery, sleep, strain, and workout data. Use for morning briefing, midday energy checks, evening wind-down, or any question about recovery, sleep, HRV, strain, or body readiness.
allowed-tools: Bash(curl*), Bash(jq*)
---

# Whoop

Fetches comprehensive daily health metrics from the Whoop API v2.

Credentials injected as environment variables — never log or expose them:
- `WHOOP_CLIENT_ID` — OAuth2 client ID
- `WHOOP_CLIENT_SECRET` — OAuth2 client secret
- `WHOOP_REFRESH_TOKEN` — bootstrap refresh token (superseded by `whoop-tokens.json`)

Token rotation is automatic — each run saves the new refresh token to
`/workspace/extra/nanoclaw-config/whoop-tokens.json`.

## Fetch all metrics

```bash
bash /home/node/.claude/skills/whoop/whoop-fetch.sh
```

Output shape:
```json
{
  "recovery": {
    "score": 53.0,
    "hrv_ms": 29.4,
    "rhr_bpm": 75.0,
    "spo2_pct": 94.0,
    "skin_temp_c": 35.4
  },
  "sleep": {
    "performance_pct": 78.0,
    "consistency_pct": 89.0,
    "efficiency_pct": 93.2,
    "total_hours": 6.5,
    "deep_hours": 1.8,
    "rem_hours": 2.5,
    "light_hours": 1.7,
    "awake_hours": 0.5,
    "cycles": 4,
    "disturbances": 5,
    "respiratory_rate": 14.6,
    "need_hours": 8.2,
    "debt_hours": 0.8,
    "is_nap": false
  },
  "cycle": {
    "strain": 8.3,
    "kilojoules": 2100,
    "avg_hr": 68,
    "max_hr": 142,
    "start": "2026-03-19T06:00:00.000Z",
    "active": true
  },
  "workout": {
    "sport": "Running",
    "strain": 14.2,
    "avg_hr": 152,
    "max_hr": 178,
    "duration_mins": 45,
    "distance_km": 8.4,
    "kilojoules": 1200,
    "zones": {"z0":2,"z1":5,"z2":10,"z3":18,"z4":8,"z5":2},
    "start": "2026-03-18T17:30:00.000Z"
  }
}
```

Any field may be `null` if not yet synced or unavailable. Handle gracefully — omit null fields from output.

## Recovery score interpretation

| Score | Colour | Descriptor |
|-------|--------|------------|
| 67–100 | 🟢 Green | Good day for high output |
| 34–66 | 🟡 Yellow | Moderate day recommended |
| 0–33 | 🔴 Red | Low recovery — protect focus time |

## Strain scale (0–21)

| Range | Label |
|-------|-------|
| 0–9 | Light |
| 10–13 | Moderate |
| 14–17 | High |
| 18–21 | All Out |

## Morning briefing format

Add a *Body* section to the briefing. Use Telegram-friendly formatting — `*bold*` labels, short lines, emoji markers:

```
💪 *Body*
Recovery: 53% 🟡 · HRV 29ms · RHR 75bpm · SpO2 94% · Skin 35.4°C
_Moderate day — structured work recommended_

😴 *Sleep*
6.5h total · Deep 1.8h · REM 2.5h · Light 1.7h · 5 disturbances
78% performance · 93% efficiency · Resp 14.6/min
Sleep need tonight: ~8.2h (0.8h debt)

🔋 *Strain* so far: 8.3/21 · Avg HR 68bpm _(in progress)_

🏃 *Last workout* — Running 45min · 8.4km · Strain 14.2/21 · Avg HR 152bpm
```

Rules:
- Omit any field that is null
- Omit an entire line if all fields in it are null
- Only include workout if `workout.start` is within the last 48 hours
- Omit the strain line if `cycle.strain` is null
- If script fails entirely, omit the Body section

## ADHD context rules

Recovery score maps directly to cognitive capacity. Use it to frame the day:

- **Green (67–100%)**: Deep work window is open. Recommend tackling the hardest task early. Hyperfocus is an asset today.
- **Yellow (34–66%)**: Time-boxed tasks work best. 25–30 min blocks. Avoid high-stakes decisions if possible.
- **Red (0–33%)**: ADHD symptoms likely worse today — higher distractibility, lower executive function. Calls, admin, and easy wins. Hard thinking can wait.

High strain (>15/21) compounds cognitive load even on green recovery days — flag this.
Sleep debt >1h is worth noting; it degrades working memory and impulse control.
