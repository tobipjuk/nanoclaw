# Task Health Skill

Read `/workspace/extra/nanoclaw-config/task-status.json` and call `mcp__nanoclaw__list_tasks` to get a combined view of Orion's scheduled task health.

## Usage

Invoke this skill when Tobi asks about task status, e.g.:
- "what tasks ran today?"
- "when did the morning briefing last fire?"
- "are any tasks stuck?"
- "task health"

## Expected intervals

Use these to determine if a task is stale (last_run older than 1.5× interval):

| key | label | interval |
|-----|-------|----------|
| `calendar-nudge` | Calendar nudge | 5 min |
| `morning-briefing` | Morning briefing | 1 day (weekdays) |
| `end-of-day-checkin` | End-of-day check-in | 1 day |
| `daily-cti-briefing` | Daily CTI briefing | 1 day (weekdays) |
| `whoop-midday` | Whoop midday check | 1 day (weekdays) |
| `whoop-evening` | Whoop wind-down | 1 day |
| `weekly-finance-checkin` | Weekly finance | 7 days |
| `midday-finance-monitor` | Midday finance monitor | 1 day (weekdays) |
| `monthly-finance-reset` | Monthly finance reset | 31 days |

## Output format

Format the health report as a table, one row per task:

```
🔧 *Task health*

✅ Morning briefing — 07:31 today
✅ Calendar nudge — 09:06 today
⚠️ Daily CTI briefing — last run 2 days ago (expected daily)
❌ Whoop wind-down — never run
```

- ✅ = ran within expected window
- ⚠️ = stale (overdue by >1.5× interval)
- ❌ = never run or error on last run
- Show last_run as relative time if today ("HH:MM today"), otherwise "N days ago"
- Append last_result summary from list_tasks output where available
- If all tasks healthy, say "All tasks running normally."
