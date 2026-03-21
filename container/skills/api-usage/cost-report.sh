#!/bin/bash
# Read this month's usage from the local usage log
# Data is captured by the agent-runner from SDK result messages

set -euo pipefail

USAGE_DIR="/workspace/extra/nanoclaw-config/usage"
MONTH=$(date -u +%Y-%m)
LOG_FILE="${USAGE_DIR}/${MONTH}.jsonl"

if [ ! -f "$LOG_FILE" ]; then
  echo '{"error": "No usage data yet for this month. Usage tracking starts from the next container run."}'
  exit 0
fi

# Output the full month's data as JSON array
echo '['
sed '$!s/$/,/' "$LOG_FILE"
echo ']'
