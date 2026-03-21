---
name: api-usage
description: Query Anthropic API usage and cost data — token counts by model, daily/hourly spend, cost breakdowns. Use whenever asked about API usage, spend, token consumption, or Claude costs.
allowed-tools: Bash(curl*), Bash(jq*), Bash(date*), Bash(cat*), Bash(echo*)
---

# Anthropic API Usage & Cost

Queries the Anthropic Admin API for usage and cost data. Requires an Admin API key.

Credentials are injected as environment variables — never log or expose them:
- `ANTHROPIC_ADMIN_KEY` — Admin API key (starts with `sk-ant-admin...`)

Base URL: `https://api.anthropic.com`
Auth header: `x-api-key: $ANTHROPIC_ADMIN_KEY`
Required header: `anthropic-version: 2023-06-01`

## Fetch today's usage by model

```bash
bash /home/node/.claude/skills/api-usage/usage-report.sh
```

Returns JSON with today's token usage grouped by model (1-hour buckets).

## Fetch cost report

```bash
bash /home/node/.claude/skills/api-usage/cost-report.sh
```

Returns JSON with this month's daily costs grouped by description (includes model info).

## Custom queries

### Daily usage for a date range (by model)

```bash
curl -s "https://api.anthropic.com/v1/organizations/usage_report/messages?\
starting_at=2026-03-01T00:00:00Z&\
ending_at=2026-03-21T00:00:00Z&\
group_by[]=model&\
bucket_width=1d" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ANTHROPIC_ADMIN_KEY"
```

### Hourly usage for a specific day

```bash
curl -s "https://api.anthropic.com/v1/organizations/usage_report/messages?\
starting_at=2026-03-21T00:00:00Z&\
ending_at=2026-03-21T23:59:59Z&\
group_by[]=model&\
bucket_width=1h" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ANTHROPIC_ADMIN_KEY"
```

### Monthly cost breakdown

```bash
curl -s "https://api.anthropic.com/v1/organizations/cost_report?\
starting_at=2026-03-01T00:00:00Z&\
ending_at=2026-04-01T00:00:00Z&\
group_by[]=description&\
bucket_width=1d" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ANTHROPIC_ADMIN_KEY"
```

## Response fields

### Usage endpoint
- `uncached_input_tokens` — input tokens not from cache
- `cache_read_input_tokens` — input tokens served from cache
- `cache_creation.ephemeral_5m_input_tokens` — tokens used to create 5-min cache
- `cache_creation.ephemeral_1h_input_tokens` — tokens used to create 1-hour cache
- `output_tokens` — tokens generated
- `server_tool_use.web_search_requests` — web search count
- `model` — model name (when grouped by model)

### Cost endpoint
- Costs are in USD cents (decimal strings)
- Groups by `description` which includes model and geo info

## Data freshness
- Usage data typically appears within 5 minutes of API request completion
- Polling supported once per minute for sustained use

## Error handling
- If `ANTHROPIC_ADMIN_KEY` is missing or empty, tell the user they need to generate an Admin API key at console.anthropic.com > Settings > Admin Keys
- Admin keys are separate from regular API keys and require admin role
