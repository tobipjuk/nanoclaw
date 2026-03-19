#!/usr/bin/env bash
# whoop-fetch.sh — Fetch today's recovery, sleep, and body metrics from Whoop API
# Usage: bash whoop-fetch.sh
# Output: JSON with recovery_score, hrv, rhr, sleep_performance, sleep_hours
#
# Environment:
#   WHOOP_CLIENT_ID      - OAuth2 client ID
#   WHOOP_CLIENT_SECRET  - OAuth2 client secret
#   WHOOP_REFRESH_TOKEN  - OAuth2 refresh token (bootstrap; superseded by tokens file)
#
# Token rotation:
#   Whoop rotates refresh tokens on every use. The current token is persisted to
#   /workspace/extra/nanoclaw-config/whoop-tokens.json (writable host mount).
#   That file takes precedence over the WHOOP_REFRESH_TOKEN env var.

set -euo pipefail

TOKENS_FILE="/workspace/extra/nanoclaw-config/whoop-tokens.json"

if [[ -z "${WHOOP_CLIENT_ID:-}" || -z "${WHOOP_CLIENT_SECRET:-}" ]]; then
  echo '{"error": "Whoop credentials not configured (WHOOP_CLIENT_ID, WHOOP_CLIENT_SECRET)"}' >&2
  exit 1
fi

# ── Resolve current refresh token ──────────────────────────────────────────────
# Prefer the persisted tokens file (rotated) over the static env var (bootstrap)

if [[ -f "$TOKENS_FILE" ]]; then
  REFRESH_TOKEN=$(jq -r '.refresh_token // empty' "$TOKENS_FILE")
fi

if [[ -z "${REFRESH_TOKEN:-}" ]]; then
  REFRESH_TOKEN="${WHOOP_REFRESH_TOKEN:-}"
fi

if [[ -z "$REFRESH_TOKEN" ]]; then
  echo '{"error": "No Whoop refresh token available — run OAuth setup to authenticate"}' >&2
  exit 1
fi

# ── Get access token ───────────────────────────────────────────────────────────

TOKEN_RESPONSE=$(curl -s -X POST "https://api.prod.whoop.com/oauth/oauth2/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "client_id=${WHOOP_CLIENT_ID}" \
  -d "client_secret=${WHOOP_CLIENT_SECRET}" \
  --data-urlencode "refresh_token=${REFRESH_TOKEN}" \
  -d "scope=offline")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
NEW_REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // empty')

if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "{\"error\": \"Failed to get Whoop access token\", \"detail\": $(echo "$TOKEN_RESPONSE" | jq -c .)}" >&2
  exit 1
fi

# Persist the rotated refresh token — must happen before any exit path below
if [[ -n "$NEW_REFRESH_TOKEN" ]]; then
  TOKENS_DIR=$(dirname "$TOKENS_FILE")
  mkdir -p "$TOKENS_DIR"
  jq -n \
    --arg rt "$NEW_REFRESH_TOKEN" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{"refresh_token": $rt, "updated_at": $updated}' > "$TOKENS_FILE"
fi

# ── Fetch latest recovery ──────────────────────────────────────────────────────

RECOVERY=$(curl -s "https://api.prod.whoop.com/developer/v2/recovery?limit=1" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}")

RECOVERY_SCORE=$(echo "$RECOVERY" | jq -r '.records[0].score.recovery_score // null')
HRV=$(echo "$RECOVERY" | jq -r '.records[0].score.hrv_rmssd_milli // null')
RHR=$(echo "$RECOVERY" | jq -r '.records[0].score.resting_heart_rate // null')

# ── Fetch latest sleep ─────────────────────────────────────────────────────────

SLEEP=$(curl -s "https://api.prod.whoop.com/developer/v2/activity/sleep?limit=1" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}")

SLEEP_PERFORMANCE=$(echo "$SLEEP" | jq -r '.records[0].score.sleep_performance_percentage // null')
SLEEP_HOURS=$(echo "$SLEEP" | jq -r '
  .records[0].score.stage_summary |
  if . != null then
    ((.total_in_bed_time_milli // 0) / 3600000 * 10 | round) / 10
  else null end')

# ── Output ─────────────────────────────────────────────────────────────────────

jq -n \
  --argjson recovery "$RECOVERY_SCORE" \
  --argjson hrv "$HRV" \
  --argjson rhr "$RHR" \
  --argjson sleep_performance "$SLEEP_PERFORMANCE" \
  --argjson sleep_hours "$SLEEP_HOURS" '{
    recovery_score: $recovery,
    hrv_ms: ($hrv | if . != null then (. * 10 | round) / 10 else null end),
    resting_heart_rate: $rhr,
    sleep_performance: $sleep_performance,
    sleep_hours: $sleep_hours
  }'
