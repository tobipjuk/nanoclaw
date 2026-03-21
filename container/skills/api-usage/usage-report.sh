#!/bin/bash
# Fetch today's API usage grouped by model (hourly buckets)
# Requires: ANTHROPIC_ADMIN_KEY environment variable

set -euo pipefail

if [ -z "${ANTHROPIC_ADMIN_KEY:-}" ]; then
  echo '{"error": "ANTHROPIC_ADMIN_KEY not set. Generate an Admin API key at console.anthropic.com > Settings > Admin Keys."}'
  exit 1
fi

TODAY=$(date -u +%Y-%m-%dT00:00:00Z)
TOMORROW=$(date -u -d "+1 day" +%Y-%m-%dT00:00:00Z)

curl -s "https://api.anthropic.com/v1/organizations/usage_report/messages?\
starting_at=${TODAY}&\
ending_at=${TOMORROW}&\
group_by[]=model&\
bucket_width=1h" \
  --header "anthropic-version: 2023-06-01" \
  --header "x-api-key: $ANTHROPIC_ADMIN_KEY"
