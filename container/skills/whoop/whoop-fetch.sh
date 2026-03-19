#!/usr/bin/env bash
# whoop-fetch.sh — Fetch comprehensive daily metrics from Whoop API v2
# Usage: bash whoop-fetch.sh
# Output: JSON with recovery, sleep stages, today's cycle/strain, and latest workout
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

# Persist the rotated refresh token immediately
if [[ -n "$NEW_REFRESH_TOKEN" ]]; then
  TOKENS_DIR=$(dirname "$TOKENS_FILE")
  mkdir -p "$TOKENS_DIR"
  jq -n \
    --arg rt "$NEW_REFRESH_TOKEN" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{"refresh_token": $rt, "updated_at": $updated}' > "$TOKENS_FILE"
fi

# ── Fetch all endpoints ────────────────────────────────────────────────────────
# Safe fetch: returns '{}' on non-JSON responses (e.g. 404 "HTTP 404 Not Found")

safe_fetch() {
  local url="$1"
  local body
  body=$(curl -s "$url" -H "Authorization: Bearer ${ACCESS_TOKEN}")
  # Validate JSON; fall back to empty object on parse error
  echo "$body" | jq -e . >/dev/null 2>&1 && echo "$body" || echo '{}'
}

RECOVERY=$(safe_fetch "https://api.prod.whoop.com/developer/v2/recovery?limit=1")
SLEEP=$(safe_fetch    "https://api.prod.whoop.com/developer/v2/activity/sleep?limit=1")
CYCLE=$(safe_fetch    "https://api.prod.whoop.com/developer/v2/cycles?limit=1")
WORKOUT=$(safe_fetch  "https://api.prod.whoop.com/developer/v2/activity/workout?limit=1")

# ── Extract recovery fields ────────────────────────────────────────────────────

RECOVERY_SCORE=$(echo "$RECOVERY"  | jq -r '.records[0].score.recovery_score // null')
HRV=$(echo "$RECOVERY"             | jq -r '.records[0].score.hrv_rmssd_milli // null')
RHR=$(echo "$RECOVERY"             | jq -r '.records[0].score.resting_heart_rate // null')
SPO2=$(echo "$RECOVERY"            | jq -r '.records[0].score.spo2_percentage // null')
SKIN_TEMP=$(echo "$RECOVERY"       | jq -r '.records[0].score.skin_temp_celsius // null')

# ── Extract sleep fields ───────────────────────────────────────────────────────

SLEEP_PERFORMANCE=$(echo "$SLEEP" | jq -r '.records[0].score.sleep_performance_percentage // null')
SLEEP_CONSISTENCY=$(echo "$SLEEP" | jq -r '.records[0].score.sleep_consistency_percentage // null')
SLEEP_EFFICIENCY=$(echo "$SLEEP"  | jq -r '.records[0].score.sleep_efficiency_percentage // null')
RESP_RATE=$(echo "$SLEEP"         | jq -r '.records[0].score.respiratory_rate // null')
IS_NAP=$(echo "$SLEEP"            | jq -r '.records[0].nap // null')

SLEEP_HOURS=$(echo "$SLEEP" | jq -r '
  .records[0].score.stage_summary |
  if . != null then ((.total_in_bed_time_milli // 0) / 3600000 * 10 | round) / 10
  else null end')

DEEP_HOURS=$(echo "$SLEEP" | jq -r '
  .records[0].score.stage_summary |
  if . != null then ((.total_slow_wave_sleep_time_milli // 0) / 3600000 * 10 | round) / 10
  else null end')

REM_HOURS=$(echo "$SLEEP" | jq -r '
  .records[0].score.stage_summary |
  if . != null then ((.total_rem_sleep_time_milli // 0) / 3600000 * 10 | round) / 10
  else null end')

LIGHT_HOURS=$(echo "$SLEEP" | jq -r '
  .records[0].score.stage_summary |
  if . != null then ((.total_light_sleep_time_milli // 0) / 3600000 * 10 | round) / 10
  else null end')

AWAKE_HOURS=$(echo "$SLEEP" | jq -r '
  .records[0].score.stage_summary |
  if . != null then ((.total_awake_time_milli // 0) / 3600000 * 10 | round) / 10
  else null end')

SLEEP_CYCLES=$(echo "$SLEEP"       | jq -r '.records[0].score.stage_summary.sleep_cycle_count // null')
DISTURBANCES=$(echo "$SLEEP"       | jq -r '.records[0].score.stage_summary.disturbance_count // null')

SLEEP_NEED_TOTAL=$(echo "$SLEEP" | jq -r '
  .records[0].score.sleep_needed |
  if . != null then
    (((.baseline_milli // 0) + (.need_from_sleep_debt_milli // 0) + (.need_from_recent_strain_milli // 0) + (.need_from_recent_nap_milli // 0))
    / 3600000 * 10 | round) / 10
  else null end')

SLEEP_NEED_DEBT=$(echo "$SLEEP" | jq -r '
  .records[0].score.sleep_needed.need_from_sleep_debt_milli // null |
  if . != null then (. / 3600000 * 10 | round) / 10 else null end')

# ── Extract cycle / strain fields ─────────────────────────────────────────────

CYCLE_STRAIN=$(echo "$CYCLE"    | jq -r '.records[0].score.strain // null')
CYCLE_KJ=$(echo "$CYCLE"        | jq -r '.records[0].score.kilojoule // null')
CYCLE_AVG_HR=$(echo "$CYCLE"    | jq -r '.records[0].score.average_heart_rate // null')
CYCLE_MAX_HR=$(echo "$CYCLE"    | jq -r '.records[0].score.max_heart_rate // null')
CYCLE_START=$(echo "$CYCLE"     | jq -r '.records[0].start // null')
CYCLE_END=$(echo "$CYCLE"       | jq -r '.records[0].end // null')  # null = current cycle

# ── Extract latest workout fields ─────────────────────────────────────────────

WORKOUT_SPORT=$(echo "$WORKOUT"   | jq -r '.records[0].sport_name // null')
WORKOUT_STRAIN=$(echo "$WORKOUT"  | jq -r '.records[0].score.strain // null')
WORKOUT_AVG_HR=$(echo "$WORKOUT"  | jq -r '.records[0].score.average_heart_rate // null')
WORKOUT_MAX_HR=$(echo "$WORKOUT"  | jq -r '.records[0].score.max_heart_rate // null')
WORKOUT_KJ=$(echo "$WORKOUT"      | jq -r '.records[0].score.kilojoule // null')
WORKOUT_START=$(echo "$WORKOUT"   | jq -r '.records[0].start // null')
WORKOUT_END=$(echo "$WORKOUT"     | jq -r '.records[0].end // null')

WORKOUT_MINS=$(echo "$WORKOUT" | jq -r '
  if .records[0].start != null and .records[0].end != null then
    ((.records[0].end | fromdateiso8601) - (.records[0].start | fromdateiso8601)) / 60 | round
  else null end')

WORKOUT_DIST_KM=$(echo "$WORKOUT" | jq -r '
  .records[0].score.distance_meter // null |
  if . != null then (. / 1000 * 10 | round) / 10 else null end')

WORKOUT_ZONES=$(echo "$WORKOUT" | jq -r '
  .records[0].score.zone_durations |
  if . != null then {
    z0: ((.zone_zero_milli // 0) / 60000 | round),
    z1: ((.zone_one_milli // 0) / 60000 | round),
    z2: ((.zone_two_milli // 0) / 60000 | round),
    z3: ((.zone_three_milli // 0) / 60000 | round),
    z4: ((.zone_four_milli // 0) / 60000 | round),
    z5: ((.zone_five_milli // 0) / 60000 | round)
  } else null end')

# ── Output ─────────────────────────────────────────────────────────────────────

jq -n \
  --argjson recovery_score   "$RECOVERY_SCORE" \
  --argjson hrv              "$HRV" \
  --argjson rhr              "$RHR" \
  --argjson spo2             "$SPO2" \
  --argjson skin_temp        "$SKIN_TEMP" \
  --argjson sleep_performance "$SLEEP_PERFORMANCE" \
  --argjson sleep_consistency "$SLEEP_CONSISTENCY" \
  --argjson sleep_efficiency  "$SLEEP_EFFICIENCY" \
  --argjson sleep_hours      "$SLEEP_HOURS" \
  --argjson deep_hours       "$DEEP_HOURS" \
  --argjson rem_hours        "$REM_HOURS" \
  --argjson light_hours      "$LIGHT_HOURS" \
  --argjson awake_hours      "$AWAKE_HOURS" \
  --argjson sleep_cycles     "$SLEEP_CYCLES" \
  --argjson disturbances     "$DISTURBANCES" \
  --argjson respiratory_rate "$RESP_RATE" \
  --argjson sleep_need_hours "$SLEEP_NEED_TOTAL" \
  --argjson sleep_debt_hours "$SLEEP_NEED_DEBT" \
  --argjson is_nap           "$IS_NAP" \
  --argjson cycle_strain     "$CYCLE_STRAIN" \
  --argjson cycle_kj         "$CYCLE_KJ" \
  --argjson cycle_avg_hr     "$CYCLE_AVG_HR" \
  --argjson cycle_max_hr     "$CYCLE_MAX_HR" \
  --arg     cycle_start      "$CYCLE_START" \
  --arg     cycle_end        "$CYCLE_END" \
  --arg     workout_sport    "$WORKOUT_SPORT" \
  --argjson workout_strain   "$WORKOUT_STRAIN" \
  --argjson workout_avg_hr   "$WORKOUT_AVG_HR" \
  --argjson workout_max_hr   "$WORKOUT_MAX_HR" \
  --argjson workout_kj       "$WORKOUT_KJ" \
  --argjson workout_mins     "$WORKOUT_MINS" \
  --argjson workout_dist_km  "$WORKOUT_DIST_KM" \
  --argjson workout_zones    "$WORKOUT_ZONES" \
  --arg     workout_start    "$WORKOUT_START" \
  '{
    recovery: {
      score: $recovery_score,
      hrv_ms: ($hrv | if . != null then (. * 10 | round) / 10 else null end),
      rhr_bpm: $rhr,
      spo2_pct: ($spo2 | if . != null then (. * 10 | round) / 10 else null end),
      skin_temp_c: ($skin_temp | if . != null then (. * 10 | round) / 10 else null end)
    },
    sleep: {
      performance_pct: $sleep_performance,
      consistency_pct: $sleep_consistency,
      efficiency_pct: $sleep_efficiency,
      total_hours: $sleep_hours,
      deep_hours: $deep_hours,
      rem_hours: $rem_hours,
      light_hours: $light_hours,
      awake_hours: $awake_hours,
      cycles: $sleep_cycles,
      disturbances: $disturbances,
      respiratory_rate: ($respiratory_rate | if . != null then (. * 10 | round) / 10 else null end),
      need_hours: $sleep_need_hours,
      debt_hours: $sleep_debt_hours,
      is_nap: $is_nap
    },
    cycle: {
      strain: ($cycle_strain | if . != null then (. * 10 | round) / 10 else null end),
      kilojoules: ($cycle_kj | if . != null then (. | round) else null end),
      avg_hr: $cycle_avg_hr,
      max_hr: $cycle_max_hr,
      start: $cycle_start,
      active: ($cycle_end == "" or $cycle_end == "null")
    },
    workout: {
      sport: (if $workout_sport == "null" then null else $workout_sport end),
      strain: ($workout_strain | if . != null then (. * 10 | round) / 10 else null end),
      avg_hr: $workout_avg_hr,
      max_hr: $workout_max_hr,
      duration_mins: $workout_mins,
      distance_km: $workout_dist_km,
      kilojoules: ($workout_kj | if . != null then (. | round) else null end),
      zones: $workout_zones,
      start: (if $workout_start == "null" then null else $workout_start end)
    }
  }'
