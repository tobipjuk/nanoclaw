#!/usr/bin/env bash
# Backup health check: alerts via Telegram if any of the four nightly
# backup scripts hasn't reported "Backup complete." within MAX_AGE_HOURS.
#
# Reads TELEGRAM_BOT_TOKEN + COUNCIL_ALLOWED_USER_ID from /root/nanoclaw/.env.
# Exits 0 if all backups healthy. Exits 1 (and alerts) if any are stale or missing.
set -euo pipefail

MAX_AGE_HOURS=${MAX_AGE_HOURS:-48}
ENV_FILE=/root/nanoclaw/.env

while IFS= read -r line; do
  [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && export "$line"
done < "$ENV_FILE"

NOW_EPOCH=$(date +%s)
MAX_AGE_SEC=$((MAX_AGE_HOURS * 3600))
FAILURES=()

check() {
  local name="$1" logfile="$2" pattern="$3"
  if [[ ! -f "$logfile" ]]; then
    FAILURES+=("$name: log file missing ($logfile)")
    return
  fi
  local line ts ts_epoch age
  line=$(grep -E "$pattern" "$logfile" 2>/dev/null | tail -1)
  if [[ -z "$line" ]]; then
    FAILURES+=("$name: no successful backup recorded in $logfile")
    return
  fi
  ts=$(echo "$line" | grep -oE "20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z" | head -1)
  if [[ -z "$ts" ]]; then
    FAILURES+=("$name: could not parse timestamp from log")
    return
  fi
  ts_epoch=$(date -d "$ts" +%s)
  age=$((NOW_EPOCH - ts_epoch))
  if (( age > MAX_AGE_SEC )); then
    FAILURES+=("$name: last success was $((age / 3600))h ago ($ts)")
  fi
}

check "nanoclaw" /root/nanoclaw/logs/backup.log '^\[20[^]]+\] Backup complete\.$'
check "obsidian" /root/nanoclaw/logs/backup.log '\[obsidian\] Backup complete\.$'
check "hex"      /root/hex/logs/backup.log      '^\[20[^]]+\] Backup complete\.$'
check "stoa"     /root/stoa/logs/backup.log     '^\[20[^]]+\] Backup complete\.$'

if (( ${#FAILURES[@]} == 0 )); then
  exit 0
fi

MSG="🚨 Backup health check failed (${#FAILURES[@]} of 4):"$'\n'
for f in "${FAILURES[@]}"; do
  MSG+=$'\n'"• $f"
done

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${COUNCIL_ALLOWED_USER_ID:-}" ]]; then
  echo "$MSG" >&2
  echo "(no Telegram credentials in .env — alert not sent)" >&2
  exit 1
fi

curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${COUNCIL_ALLOWED_USER_ID}" \
  --data-urlencode "text=${MSG}" > /dev/null

echo "$MSG" >&2
exit 1
