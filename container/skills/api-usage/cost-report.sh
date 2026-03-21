#!/bin/bash
# Fetch this month's cost report grouped by description (daily buckets)
# Requires: ANTHROPIC_ADMIN_KEY environment variable

set -euo pipefail

if [ -z "${ANTHROPIC_ADMIN_KEY:-}" ]; then
  echo '{"error": "ANTHROPIC_ADMIN_KEY not set. Generate an Admin API key at console.anthropic.com > Settings > Admin Keys."}'
  exit 1
fi

MONTH_START=$(date -u +%Y-%m-01T00:00:00Z)
# Next month start
NEXT_MONTH=$(date -u -d "$(date -u +%Y-%m-01) +1 month" +%Y-%m-01T00:00:00Z)

curl -s "https://api.anthropic.com/v1/organizations/cost_report?\
starting_at=${MONTH_START}&\
ending_at=${NEXT_MONTH}&\
group_by[]=description&\
bucket_width=1d" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ANTHROPIC_ADMIN_KEY"
