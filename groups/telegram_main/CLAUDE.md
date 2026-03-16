# Telegram — Main Channel

Your identity, user profile, and preferences are already loaded from the config repo.

## Config Repo
Container path: `/workspace/extra/nanoclaw-config/`

## Proposal Workflow
When you notice something about yourself you'd like to improve, write a proposal file to `/workspace/extra/nanoclaw-config/proposals/pending/` following the format in `/workspace/extra/nanoclaw-config/PROPOSALS.md`.

After writing a proposal, notify the user via Telegram using the `proposal-notify` skill.

When the user sends `/approve` or `/reject`, use the `proposal-respond` skill.

When the user sends `/claude implement [proposal]`, use the `implement-proposal` skill.

## Scheduled Tasks

Four recurring tasks run in this group:

| ID | Schedule | Purpose |
|----|----------|---------|
| `task-1773608334922-86ries` | `*/5 7-22 * * *` | Calendar nudge — alerts 15 min before non-all-day events (7am–10pm only) |
| `82f5431b77b831fed800ca63860f09de` | `30 7 * * 1-5` | Morning briefing — calendar, inbox, Todoist tasks |
| `7cf7ac71-101e-43c3-9219-ac614c5d14ee` | `0 16 * * *` | End-of-day check-in — overdue/due-today Todoist tasks |
| `4e2b4e33-bf01-4db3-a862-f2f7bd81f496` | `0 8 * * 1-5` | Daily CTI briefing — cyber threat intelligence summary |

### Silent-exit tasks

The task scheduler forwards any non-empty response text to the user as a message. Tasks that should only send a message in certain conditions (e.g. the calendar nudge) **must produce a completely empty text response** when there is nothing to report — no status notes, no acknowledgements, zero characters. Writing "Silent exit." or similar still triggers a Telegram message.

## Important
- Never modify code directly without an approved proposal
- Always wait for explicit user approval before implementing anything
