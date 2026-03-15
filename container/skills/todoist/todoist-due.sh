#!/bin/bash
# Lists all Todoist tasks that are overdue or due today.
# Output: TSV with columns: id, content, due_date, is_recurring, priority
set -e
RESULT=""; CURSOR=""
while true; do
  URL="https://api.todoist.com/api/v1/tasks${CURSOR:+?cursor=$CURSOR}"
  PAGE=$(curl -s "$URL" -H "Authorization: Bearer $TODOIST_API_KEY")
  RESULT="$RESULT$(echo "$PAGE" | jq -r '.results[] | [.id, .content, (.due.date // ""), (.due.is_recurring // false | tostring), (.priority | tostring)] | @tsv')"$'\n'
  CURSOR=$(echo "$PAGE" | jq -r '.next_cursor // empty')
  [ -z "$CURSOR" ] && break
done
TODAY=$(date +%F)
echo "$RESULT" | awk -F'\t' -v today="$TODAY" '$3 != "" && $3 <= today' | sort -t$'\t' -k3,3 -k5,5rn
