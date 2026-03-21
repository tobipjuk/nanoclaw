---
name: api-usage
description: Query Orion's API usage and cost data — token counts by model, daily spend, cost breakdowns. Use whenever asked about API usage, spend, token consumption, or Claude costs.
allowed-tools: Bash(bash*), Bash(jq*), Bash(date*), Bash(cat*), Bash(grep*), Bash(awk*)
---

# Orion API Usage & Cost Tracking

Reads usage data from local logs. Every container run automatically logs token counts, costs, and model breakdown to JSONL files in `/workspace/extra/nanoclaw-config/usage/`.

## Fetch today's usage

```bash
bash /home/node/.claude/skills/api-usage/usage-report.sh
```

Returns JSON array of today's usage entries.

## Fetch this month's usage

```bash
bash /home/node/.claude/skills/api-usage/cost-report.sh
```

Returns JSON array of all entries for the current month.

## Read a specific month

```bash
cat /workspace/extra/nanoclaw-config/usage/YYYY-MM.jsonl
```

## Log entry format

Each line in the JSONL is one container run:

```json
{
  "timestamp": "2026-03-21T14:30:00.000Z",
  "group": "main",
  "model": "claude-haiku-4-5-20251001",
  "is_scheduled_task": true,
  "total_cost_usd": 0.0234,
  "duration_ms": 15000,
  "duration_api_ms": 8000,
  "num_turns": 3,
  "usage": {
    "input_tokens": 5000,
    "output_tokens": 1200,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 3000
  },
  "model_usage": {
    "claude-haiku-4-5-20251001": {
      "inputTokens": 5000,
      "outputTokens": 1200,
      "cacheReadInputTokens": 3000,
      "cacheCreationInputTokens": 0,
      "costUSD": 0.0234
    }
  }
}
```

## Aggregation with jq

### Total cost today
```bash
bash /home/node/.claude/skills/api-usage/usage-report.sh | jq '[.[].total_cost_usd] | add // 0'
```

### Cost by model today
```bash
bash /home/node/.claude/skills/api-usage/usage-report.sh | jq 'group_by(.model) | map({model: .[0].model, cost: ([.[].total_cost_usd] | add), runs: length})'
```

### Month-to-date total
```bash
bash /home/node/.claude/skills/api-usage/cost-report.sh | jq '[.[].total_cost_usd] | add // 0'
```

### Scheduled vs interactive breakdown
```bash
bash /home/node/.claude/skills/api-usage/cost-report.sh | jq 'group_by(.is_scheduled_task) | map({scheduled: .[0].is_scheduled_task, cost: ([.[].total_cost_usd] | add), runs: length})'
```

### Daily cost trend
```bash
bash /home/node/.claude/skills/api-usage/cost-report.sh | jq 'group_by(.timestamp[:10]) | map({date: .[0].timestamp[:10], cost: ([.[].total_cost_usd] | add), runs: length})'
```

## Key fields

- `total_cost_usd` — USD cost for this run (from SDK)
- `usage.input_tokens` — uncached input tokens
- `usage.output_tokens` — generated tokens
- `usage.cache_read_input_tokens` — tokens served from cache
- `usage.cache_creation_input_tokens` — tokens used to create cache
- `model_usage` — per-model breakdown (when multiple models used via subagents)
- `is_scheduled_task` — distinguishes cron jobs from interactive messages
- `duration_ms` — wall-clock time; `duration_api_ms` — API call time only

## Data availability

- Usage tracking starts from when the agent-runner update is deployed
- Pre-deployment spend for March 2026 is seeded in config.json ($34.83)
- Each month gets its own file (YYYY-MM.jsonl)
- Data is written immediately after each container run completes

## Budget config

```bash
cat /workspace/extra/nanoclaw-config/usage/config.json
```

Fields:
- `monthly_budget_usd` — target monthly spend (default: $50)
- `daily_alert_threshold_usd` — flag days exceeding this ($5)
- `pre_tracking_spend.{YYYY-MM}` — known spend before tracking was deployed (seeded from console)

When reporting, add `pre_tracking_spend` for the month to tracked JSONL totals to get the true MTD figure.

To update the budget:
```bash
jq '.monthly_budget_usd = 75' /workspace/extra/nanoclaw-config/usage/config.json > /tmp/cfg.json && mv /tmp/cfg.json /workspace/extra/nanoclaw-config/usage/config.json
```
