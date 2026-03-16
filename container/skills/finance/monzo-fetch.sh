#!/usr/bin/env bash
# monzo-fetch.sh — Fetch current-month transactions from Monzo Google Sheet,
# merged with any manual CSV exports in the finance folder.
# Usage: bash monzo-fetch.sh
# Output: JSON array of {transaction_id, date, time, type, name, category, amount}
#
# Environment:
#   GOOGLE_SHEETS_SA_KEY  - base64-encoded service account JSON key
#   MONZO_SHEET_ID        - Google Sheet ID
#   FINANCE_DIR           - path to finance folder (default: /workspace/extra/nanoclaw-shared/finance)

set -euo pipefail

FINANCE_DIR="${FINANCE_DIR:-/workspace/extra/nanoclaw-shared/finance}"
CURRENT_MONTH=$(date +%Y-%m)

# ── Fetch from Google Sheet ────────────────────────────────────────────────────

SHEET_JSON="[]"

if [[ -n "${GOOGLE_SHEETS_SA_KEY:-}" && -n "${MONZO_SHEET_ID:-}" ]]; then
  SA_JSON=$(echo "$GOOGLE_SHEETS_SA_KEY" | base64 -d)
  CLIENT_EMAIL=$(echo "$SA_JSON" | jq -r '.client_email')
  PRIVATE_KEY=$(echo "$SA_JSON"  | jq -r '.private_key')

  NOW=$(date +%s)
  EXP=$((NOW + 3600))

  HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
  PAYLOAD=$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/spreadsheets.readonly","aud":"https://oauth2.googleapis.com/token","iat":%d,"exp":%d}' \
    "$CLIENT_EMAIL" "$NOW" "$EXP" \
    | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

  SIGNING_INPUT="${HEADER}.${PAYLOAD}"
  SIGNATURE=$(printf '%s' "$SIGNING_INPUT" \
    | openssl dgst -sha256 -sign <(printf '%s' "$PRIVATE_KEY") \
    | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

  JWT="${SIGNING_INPUT}.${SIGNATURE}"

  TOKEN_RESPONSE=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${JWT}")

  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

  if [[ -n "$ACCESS_TOKEN" ]]; then
    SHEET_NAME="Personal Account Transactions"
    ENCODED_SHEET=$(printf '%s' "$SHEET_NAME" | jq -sRr @uri)

    SHEET_DATA=$(curl -s \
      "https://sheets.googleapis.com/v4/spreadsheets/${MONZO_SHEET_ID}/values/${ENCODED_SHEET}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")

    if ! echo "$SHEET_DATA" | jq -e '.error' > /dev/null 2>&1; then
      SHEET_JSON=$(echo "$SHEET_DATA" | jq --arg month "$CURRENT_MONTH" '
        .values as $rows |
        $rows[0] as $headers |
        $rows[1:] |
        map(
          . as $row |
          ($headers | to_entries | map({key: .value, value: ($row[.key] // "")}) | from_entries)
        ) |
        map(select(
          (.Date | split("/") | if length == 3 then
            "\(.[2])-\(.[1] | if length == 1 then "0" + . else . end)-\(.[0] | if length == 1 then "0" + . else . end)"
          else "" end) | startswith($month)
        )) |
        map({
          transaction_id: (."Transaction ID" // ""),
          date: (.Date | split("/") | if length == 3 then
            "\(.[2])-\(.[1] | if length == 1 then "0" + . else . end)-\(.[0] | if length == 1 then "0" + . else . end)"
          else .Date end),
          time: .Time,
          type: .Type,
          name: .Name,
          category: .Category,
          amount: (.Amount | tonumber)
        })
      ')
    fi
  fi
fi

# ── Merge with any CSV supplements ────────────────────────────────────────────
# CSVs in FINANCE_DIR override/supplement sheet data for the same transaction IDs.
# This handles the transition period where card payments were from the Allowance Pot
# and didn't appear in the sheet.

CSV_JSON="[]"

if [[ -d "$FINANCE_DIR" ]]; then
  for CSV_FILE in "$FINANCE_DIR"/*.csv; do
    [[ -f "$CSV_FILE" ]] || continue

    # Parse CSV: Transaction ID,Date,Time,Type,Name,Emoji,Category,Amount,...
    FILE_JSON=$(python3 - "$CSV_FILE" "$CURRENT_MONTH" <<'PYEOF'
import csv, sys, json

csv_file = sys.argv[1]
month = sys.argv[2]

rows = []
with open(csv_file, newline='', encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    for row in reader:
        raw_date = row.get('Date', '')
        # Convert DD/MM/YYYY to YYYY-MM-DD
        parts = raw_date.split('/')
        if len(parts) == 3:
            iso_date = f"{parts[2]}-{parts[1].zfill(2)}-{parts[0].zfill(2)}"
        else:
            iso_date = raw_date

        if not iso_date.startswith(month):
            continue

        try:
            amount = float(row.get('Amount', 0))
        except ValueError:
            amount = 0.0

        rows.append({
            'transaction_id': row.get('Transaction ID', ''),
            'date': iso_date,
            'time': row.get('Time', ''),
            'type': row.get('Type', ''),
            'name': row.get('Name', ''),
            'category': row.get('Category', ''),
            'amount': amount,
        })

print(json.dumps(rows))
PYEOF
    )

    CSV_JSON=$(jq -s '.[0] + .[1]' <(echo "$CSV_JSON") <(echo "$FILE_JSON"))
  done
fi

# ── Merge: CSV takes priority (has card payments sheet doesn't) ────────────────
# Build a map from sheet data, then overlay CSV entries by transaction_id.

jq -n \
  --argjson sheet "$SHEET_JSON" \
  --argjson csv "$CSV_JSON" '
  # Index sheet by transaction_id
  ($sheet | map({key: .transaction_id, value: .}) | from_entries) as $sheet_map |
  # Index csv by transaction_id
  ($csv | map({key: .transaction_id, value: .}) | from_entries) as $csv_map |
  # Merge: start with sheet, overlay csv (csv wins on conflict)
  ($sheet_map * $csv_map) |
  to_entries | map(.value) |
  sort_by(.date, .time)
'
