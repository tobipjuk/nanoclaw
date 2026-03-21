#!/bin/bash
# Read today's usage from the local usage log
# Data is captured by the agent-runner from SDK result messages

set -euo pipefail

USAGE_DIR="/workspace/extra/nanoclaw-config/usage"
MONTH=$(date -u +%Y-%m)
LOG_FILE="${USAGE_DIR}/${MONTH}.jsonl"
TODAY=$(date -u +%Y-%m-%d)

if [ ! -f "$LOG_FILE" ]; then
  echo '{"error": "No usage data yet. Usage tracking starts from the next container run."}'
  exit 0
fi

# Filter to today's entries and output as JSON array
echo '['
grep "\"timestamp\":\"${TODAY}" "$LOG_FILE" | sed '$!s/$/,/'
echo ']'
