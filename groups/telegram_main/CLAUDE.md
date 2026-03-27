# Telegram — Main Channel

Your identity, user profile, and preferences are already loaded from the config repo.

## Config Repo
Container path: `/workspace/extra/nanoclaw-config/`

## Proposal Workflow
When you notice something about yourself you'd like to improve, write a proposal file to `/workspace/extra/obsidian-vault/Projects/Proposals/pending/` following the format below. Lifecycle: pending → approved → implemented (or rejected).

Filename: `YYYY-MM-DD-short-description.md`
Contents: **What** / **Why** / **How** / **Risk**

After writing a proposal, notify the user via Telegram using the `proposal-notify` skill.

When the user sends `/approve` or `/reject`, use the `proposal-respond` skill.

When the user sends `/claude implement [proposal]`, use the `implement-proposal` skill.

## Scheduled Tasks

Active recurring tasks, in schedule order:

| ID | Schedule | Model | Purpose |
|----|----------|-------|---------|
| `outlook-to-todoist-sync` | `*/15 * * * *` | Opus | Outlook → Todoist sync — runs `run_outlook.sh`, silent, script handles error alerting |
| `whoop-data-refresh` | `0,30 6-23 * * *` | Haiku | Whoop cache refresh — writes to `nanoclaw-config/whoop-cache.json`, silent |
| `25005f77-e01d-4fa0-a93a-8290f056ddd3` | `0 7 1 * *` | Haiku | Monthly finance reset (1st of month) |
| `82f5431b77b831fed800ca63860f09de` | `30 7 * * 1-5` | default | Morning briefing — Whoop, calendar, inbox, Todoist tasks, task health |
| `task-1774304794208-4ejs4j` | `0 8 * * *` | default | Todoist blog check — alerts only if new posts found |
| `newsletter-calendar-sync` | `15 8 * * 1-5` | Opus | School newsletter → Family calendar sync — runs `run_newsletter.sh`, silent |
| `task-1774297478684-5xel9k` | `0 9 * * 1` | default | LinkedIn draft (Monday) — saves to Obsidian vault |
| `task-1774297483757-7fq4rr` | `0 9 * * 4` | default | LinkedIn draft (Thursday) — saves to Obsidian vault |
| `3d8da632-652e-4ca8-b50b-e064bdd89c25` | `0 12 * * 1-5` | Haiku | Midday finance monitor — alerts only on new £100 milestones |
| `whoop-midday-energy-check` | `30 12 * * 1-5` | Haiku | Midday energy check — **sends only when recovery is Yellow or Red (≤66%); silent on Green** |
| `task-1774299572886-jfcgef` | `0 17 * * 1-5` | default | End-of-day close-out — open tasks + shutdown questions; **includes finance summary on Fridays** |
| `task-1774299672691-ezjlzn` | `0 18 * * 3` | default | Van sale nudge (Wednesday) — only if no activity in past 7 days |
| `task-1774472953451-fmzbze` | `0 19 * * *` | default | Sleep coach — schedules a bedtime reminder 1h before Whoop recommendation; silent if no data |
| `task-1774299467478-aq7gyu` | `0 19 * * 0` | default | Mind sweep nudge (Sunday) |
| `whoop-evening-winddown` | `0 21 * * *` | Haiku | Evening wind-down — sleep need, target bedtime, ADHD sleep nudge |

Paused tasks (do not re-enable without checking for conflicts):

| ID | Was | Replaced by |
|----|-----|-------------|
| `7cf7ac71-101e-43c3-9219-ac614c5d14ee` | Daily 16:00 end-of-day check-in | Merged into `task-1774299572886-jfcgef` at 17:00 |
| `0348792a-a88a-4636-955f-737129113b95` | Friday 17:00 weekly finance check-in | Merged into `task-1774299572886-jfcgef` (Fridays) |

Other paused: `4e2b4e33` (daily CTI briefing — moved to Hex), task-nudge-morning/midday/evening/weekend (superseded).

Model column: `default` = Sonnet 4.6 (inherited), `Haiku` = claude-haiku-4-5-20251001, `Opus` = claude-opus-4-6.

### Task health monitoring

Every task writes its run status to `/workspace/extra/nanoclaw-config/task-status.json` on completion (including silent exits). When asked about task health or "what ran today", use the `task-health` skill or read the status file directly.

### Messaging from scheduled tasks

The task scheduler does **not** forward the agent's text response to Telegram. All user-visible output must go through the `send_message` MCP tool. Text output is captured for internal logging only.

Wrap any internal notes or status summaries in `<internal>` tags if producing them — they will be stripped before delivery. For truly silent tasks, produce no output at all.

## Formatting

Messages are read in Telegram. Use formatting that renders well there:

- **Bold** (`*text*`) for headings and emphasis
- `monospace` for code, paths, IDs, and commands
- Plain dashes (`-`) or numbers for lists
- Avoid markdown tables — use plain lists or `key: value` lines instead
- Avoid `###` headings — use bold text instead
- Keep responses concise; don't pad with filler

## Important
- Never modify code directly without an approved proposal
- Always wait for explicit user approval before implementing anything
