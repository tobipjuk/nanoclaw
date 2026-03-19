---
name: whoop
description: Fetch today's Whoop recovery score, HRV, resting heart rate, and sleep performance. Use whenever asked about recovery, sleep, health, energy, or HRV.
allowed-tools: Bash(curl*), Bash(jq*)
---

# Whoop

Fetches daily recovery and sleep metrics from the Whoop API v1.

Credentials are injected as environment variables — never log or expose them:
- `WHOOP_CLIENT_ID` — OAuth2 client ID
- `WHOOP_CLIENT_SECRET` — OAuth2 client secret
- `WHOOP_REFRESH_TOKEN` — OAuth2 refresh token (long-lived)

## Fetch today's metrics

```bash
bash /home/node/.claude/skills/whoop/whoop-fetch.sh
```

Output:
```json
{
  "recovery_score": 84,
  "hrv_ms": 68.2,
  "resting_heart_rate": 52,
  "sleep_performance": 91,
  "sleep_hours": 7.4
}
```

## Recovery score interpretation

| Score | Label | Descriptor |
|---|---|---|
| 67–100 | Green | good day for high output |
| 34–66 | Yellow | moderate day recommended |
| 0–33 | Red | low recovery — protect focus time |

## Morning briefing format

```
💪 Recovery: 84% · HRV 68ms · Sleep 91% (7.4h) · RHR 52bpm — good day for high output
```

If recovery data is unavailable (e.g. Whoop not worn), omit the line entirely rather than showing an error.

## Guidelines

- Always use the most recent record (limit=1) — Whoop returns latest first
- HRV is in milliseconds (rmssd); round to 1 decimal place
- Sleep hours derived from total_in_bed_time_milli — round to 1 decimal
- If any individual field is null, omit it from the briefing line rather than showing "null"
