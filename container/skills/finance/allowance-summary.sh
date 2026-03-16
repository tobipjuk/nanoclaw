#!/usr/bin/env bash
# allowance-summary.sh — Calculate allowance spending and remaining balance
# Usage: bash allowance-summary.sh <transactions.json> [config.json]
# Output: JSON summary with allowance balance and category totals
#
# Budget model: fixed monthly allowance from config (default £1,000).
# Spending = card payments + personal direct debits (excludes pot transfers and transfers).

set -euo pipefail

INPUT_FILE="${1:-/tmp/monzo-raw.json}"
CONFIG_FILE="${2:-/workspace/extra/nanoclaw-config/finance/config.json}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo '{"error": "Input file not found: '"$INPUT_FILE"'"}' >&2
  exit 1
fi

# Read monthly allowance from config, default to 1000
ALLOWANCE_MONTHLY=1000
if [[ -f "$CONFIG_FILE" ]]; then
  ALLOWANCE_MONTHLY=$(jq -r '.allowance_monthly // 1000' "$CONFIG_FILE")
fi

MONTH=$(date +%Y-%m)
DAYS_IN_MONTH=$(python3 -c "import calendar, datetime; d=datetime.datetime.now(); print(calendar.monthrange(d.year, d.month)[1])")
DAY_OF_MONTH=$(date +%-d)
DAYS_LEFT=$((DAYS_IN_MONTH - DAY_OF_MONTH))

jq \
  --arg month "$MONTH" \
  --argjson allowance "$ALLOWANCE_MONTHLY" \
  --argjson days_left "$DAYS_LEFT" \
  --argjson day_of_month "$DAY_OF_MONTH" \
  --argjson days_in_month "$DAYS_IN_MONTH" '
  . as $txns |

  # Personal transaction filter: card payments, Monzo-to-Monzo, and personal Faster payments.
  # Excludes: Pot transfers (internal), Direct Debits (bills via Fixed Expenses Pot),
  #           Instalment loans (Repayments Pot), Transfers category, Income category.
  ($txns | map(select(
    .type != "Pot transfer" and
    .type != "Direct Debit" and
    .type != "Instalment loan" and
    (.category | ascii_downcase) != "transfers" and
    (.category | ascii_downcase) != "income"
  ))) as $personal_txns |

  # Outgoing spend (negative amounts)
  ($personal_txns | map(select(.amount < 0))) as $spending_txns |

  # Incoming offsets: refunds, bill splits, friend repayments (positive amounts)
  ($personal_txns | map(select(.amount > 0))) as $incoming_txns |

  # Group OUTGOING by category for the breakdown (flip sign for display)
  ($spending_txns | group_by(.category) | map({
    key: (.[0].category | gsub(" "; "_") | ascii_downcase),
    value: (map(.amount * -1) | add | (. * 100 | round) / 100)
  }) | from_entries) as $spend_by_category |

  # Net spend = outgoing - incoming offsets
  ($spending_txns | map(.amount * -1) | add // 0) as $gross_spent |
  ($incoming_txns | map(.amount) | add // 0) as $total_received |
  ($gross_spent - $total_received | (. * 100 | round) / 100) as $total_spent |

  ($allowance - $total_spent | (. * 100 | round) / 100) as $allowance_remaining |

  # Pace: daily average so far → projected month total
  (if $day_of_month > 0 then ($total_spent / $day_of_month) * $days_in_month else 0 end | (. * 100 | round) / 100) as $projected_spend |
  ($allowance - $projected_spend | (. * 100 | round) / 100) as $projected_remaining |

  {
    month: $month,
    allowance_monthly: $allowance,
    gross_spent: ($gross_spent | (. * 100 | round) / 100),
    total_received: ($total_received | (. * 100 | round) / 100),
    total_spent: $total_spent,
    allowance_remaining: $allowance_remaining,
    spend_by_category: $spend_by_category,
    days_left: $days_left,
    days_in_month: $days_in_month,
    projected_spend: $projected_spend,
    projected_remaining: $projected_remaining
  }
' "$INPUT_FILE"
