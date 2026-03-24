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

A background task refreshes `/workspace/extra/nanoclaw-config/whoop-cache.json` every 30 minutes (6am–11pm). Always read from cache — it is guaranteed to be recent. Only fall back to a live fetch if the cache is missing or older than 35 minutes.

```bash
CACHE=/workspace/extra/nanoclaw-config/whoop-cache.json
CACHE_AGE=$(( $(date +%s) - $(date -r "$CACHE" +%s 2>/dev/null || echo 0) ))
if [[ -f "$CACHE" && $CACHE_AGE -lt 2100 ]]; then
  cat "$CACHE"
else
  bash /home/node/.claude/skills/whoop/whoop-fetch.sh
fi
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

## Progress bars

Use 10-character `▓░` bars to give instant visual context for scores and fills. Rules:
- Recovery: `filled = round(score / 10)`, e.g. 53% → 5 filled → `▓▓▓▓▓░░░░░`
- Sleep fill: `filled = min(10, round(total_hours / need_hours * 10))`, e.g. 6.5/9.8h → 7 filled → `▓▓▓▓▓▓▓░░░`
- Strain: `filled = round(strain / 21 * 10)`, e.g. 4.4/21 → 2 filled → `▓▓░░░░░░░░`

## On-demand format (direct questions about Whoop stats)

When Tobi asks directly ("how's my Whoop stats", "what's my recovery", etc.), reply with **only** the block below — no preamble, no trailing paragraph, no "---" separator.

```
💪 *Recovery* — 53% 🟡  ▓▓▓▓▓░░░░░  HRV 29ms

😴 *Sleep* — 6.5h / 9.8h needed  ▓▓▓▓▓▓▓░░░
78% performance · 93% efficiency · ⚠️ 2.1h debt

🔋 *Strain* — 4.4 / 21  ▓▓░░░░░░░░  _(cycle in progress)_
Avg HR 68bpm

🏃 *Today's workout* — Walking · 60min · Avg HR 97bpm · Max 132bpm

_Moderate day. 2.1h sleep debt is the main flag — aim for an early night._
```

Fields to show — **exactly these, nothing else**:
- Recovery: score %, colour emoji, bar, HRV
- Sleep: total hours, sleep need hours, bar, performance %, efficiency %, debt flag
- Strain: score/21, bar, avg HR
- Workout: sport, duration, avg HR, max HR

Fields to **never** show (even if available):
- RHR, SpO2, skin temp
- Deep hours, REM hours, light hours, awake hours, disturbances, respiratory rate, sleep cycles, sleep consistency

Other rules:
- No opening line — start directly with the first emoji
- Progress bar on the same line as the header, after two spaces
- One italicised summary line at the end: recovery colour + any notable flags (debt ≥1h, strain >15)
- Omit any field that is null; omit an entire line if all its fields are null
- Only include workout if `workout.start` is **today** (Europe/London date)
- Omit strain line if `cycle.strain` is null
- If sleep need is null, omit the "/ Xh needed" part and skip the bar

## Morning briefing format

Add a *Body* section to the briefing using the same visual style:

```
💪 *Body*
Recovery: 53% 🟡  ▓▓▓▓▓░░░░░  HRV 29ms
_Moderate day — structured work recommended_

😴 *Sleep* — 6.5h / 9.8h  ▓▓▓▓▓▓▓░░░  · ⚠️ 2.1h debt
78% performance · 93% efficiency

🔋 *Strain* so far: 4.4 / 21  ▓▓░░░░░░░░  · Avg HR 68bpm

🏃 *Today's workout* — Walking · 60min · Avg HR 97bpm
```

Fields to show — **exactly these, nothing else**:
- Recovery: score %, colour emoji, bar, HRV
- Sleep: total hours, sleep need hours, bar, debt flag, performance %, efficiency %
- Strain: score/21, bar, avg HR
- Workout: sport, duration, avg HR

Fields to **never** show (even if available in the data):
- RHR, SpO2, skin temp
- Deep hours, REM hours, light hours, awake hours, disturbances, respiratory rate, sleep cycles, sleep consistency

Other rules:
- Omit any field that is null; omit an entire line if all its fields are null
- Only include workout if `workout.start` is **today** (Europe/London date)
- Omit the strain line if `cycle.strain` is null
- If script fails entirely, omit the Body section

## ADHD context rules

Recovery score maps directly to cognitive capacity. Use it to frame the day:

- **Green (67–100%)**: Deep work window is open. Recommend tackling the hardest task early. Hyperfocus is an asset today.
- **Yellow (34–66%)**: Time-boxed tasks work best. 25–30 min blocks. Avoid high-stakes decisions if possible.
- **Red (0–33%)**: ADHD symptoms likely worse today — higher distractibility, lower executive function. Calls, admin, and easy wins. Hard thinking can wait.

High strain (>15/21) compounds cognitive load even on green recovery days — flag this.
Sleep debt >1h is worth noting; it degrades working memory and impulse control.
