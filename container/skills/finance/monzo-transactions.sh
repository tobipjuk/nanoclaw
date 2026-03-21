#!/usr/bin/env bash
# monzo-transactions.sh — Return allowance-relevant transactions (pre-filtered)
# Usage: bash monzo-transactions.sh [transactions.json]
# If no file given, fetches fresh data via monzo-fetch.sh.
# Output: JSON array of transactions excluding Pot transfers, Direct Debits,
#         Instalment loans, Transfers category, and Income category.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${1:-}" && -f "${1}" ]]; then
  INPUT_FILE="$1"
else
  INPUT_FILE="/tmp/monzo-raw.json"
  bash "$SCRIPT_DIR/monzo-fetch.sh" > "$INPUT_FILE"
fi

jq '[.[] | select(
  .type != "Pot transfer" and
  .type != "Direct Debit" and
  .type != "Instalment loan" and
  (.category | ascii_downcase) != "transfers" and
  (.category | ascii_downcase) != "income"
)]' "$INPUT_FILE"
