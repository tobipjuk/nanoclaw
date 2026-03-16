---
name: finance
description: Read Tobi's Monzo transaction data from Google Sheets and provide personal finance insights — allowance pot balance, spending by category, weekly check-ins, and proactive alerts. Use whenever asked about money, spending, allowance, budget, or transactions.
allowed-tools: Bash(curl*), Bash(jq*), Bash(cat*), Bash(echo*), Bash(date*), Bash(mkdir*), Bash(cp*)
---

# Finance (Monzo via Google Sheets)

Reads Tobi's Monzo transaction data from Google Sheets (read-only). Never writes to the sheet.

Credentials are injected as environment variables — never log or expose them:
- `GOOGLE_SHEETS_SA_KEY` — Service account JSON key (base64-encoded)
- `MONZO_SHEET_ID` — Google Sheet ID

Config and state are stored in `/workspace/extra/nanoclaw-config/finance/`:
- `config.json` — allowance amount and alert thresholds
- `state/YYYY-MM.json` — monthly state (updated each check-in)

## Financial Structure

```
Salary → Monzo Main Account
  → Fixed Expenses Pot  (bills — excluded from allowance tracking)
  → Repayments Pot      (savings/debt — excluded from allowance tracking)
  → £1,000/month stays in main account for personal spending (PRIMARY FOCUS)
```

**Never read the `Joint Account Transactions` tab** — always use `Personal Account Transactions` only.

## Allowance model

The allowance is £1,000/month (from config). Spending is tracked from **card payments** and personal peer-to-peer transfers. Excluded: Direct Debits (bills via Fixed Expenses Pot), Instalment loans (Repayments Pot), Pot transfers, and Transfers-category transactions.

## Fetch transactions for the current month

Run `monzo-fetch.sh` to get this month's transactions as JSON. It merges Google Sheets data with any manual CSV exports in the finance folder:

```bash
bash /home/node/.claude/skills/finance/monzo-fetch.sh
```

Output: JSON array of `{transaction_id, date, time, type, name, category, amount}` for the current month.

The script automatically reads any `.csv` files from `/workspace/extra/nanoclaw-shared/finance/` and merges them with the Google Sheet data (CSV wins on duplicate transaction IDs). This handles the March 2026 transition period where card payments from the Allowance Pot were in a manual export.

## Calculate allowance summary

```bash
bash /home/node/.claude/skills/finance/monzo-fetch.sh > /tmp/monzo-raw.json
bash /home/node/.claude/skills/finance/allowance-summary.sh /tmp/monzo-raw.json /workspace/extra/nanoclaw-config/finance/config.json
```

Output: JSON with `allowance_monthly`, `total_spent`, `allowance_remaining`, `spend_by_category`, `projected_spend`, `projected_remaining`.

## Sheet columns

`Transaction ID, Date, Time, Type, Name, Emoji, Category, Amount, Currency, Local amount, Local currency, Notes and #tags, Address, Receipt, Description, Category split`

Key transaction types:
- `Pot transfer` + Name `Allowance Pot` — pot movements (negative = money loaded IN, positive = money withdrawn OUT)
- `Pot transfer` + Name `Fixed Expenses Pot` — bills
- Card payments / contactless — actual spending (grouped by Category for breakdown)

## State file format

Write state to `/workspace/extra/nanoclaw-config/finance/state/YYYY-MM.json` after each check-in:

```json
{
  "month": "2026-03",
  "last_updated": "2026-03-14T17:00:00Z",
  "allowance_loaded": 1000.00,
  "allowance_withdrawn": 420.50,
  "allowance_remaining": 579.50,
  "spend_by_category": {
    "eating_out": 85.20,
    "shopping": 143.50,
    "transport": 42.80,
    "entertainment": 35.00,
    "other": 114.00
  },
  "alerts_fired": ["milestone_100", "milestone_200", "milestone_300", "milestone_400"]
}
```

`alerts_fired` tracks which £100 milestones have been sent this month to avoid duplicates.

## Weekly check-in message format

```
📊 Weekly Finance Check-in — w/c 9 Mar

Allowance Pot: £579 remaining of £1,000
▓▓▓▓▓▓░░░░  42% spent  |  15 days left in March

You're on a good pace — projected to finish the month with ~£350 left.

Spending by category this month:
• Shopping       £143
• Eating out      £85
• Transport       £43
• Entertainment   £35
• Other          £114

Notable transactions this week:
• 10 Mar — Amazon £47.20
• 11 Mar — Deliveroo £18.50
• 13 Mar — ASOS £96.30
```

Use *bold* (single asterisks) for Telegram. No markdown headings.

## Alert message format (fires at each £100 milestone)

```
💸 Allowance — £400 spent

£600 remaining of £1,000  |  16 Mar  |  15 days left

Spent this month by category:
• Shopping       £182
• Eating out      £95
• Transport       £68
• Entertainment   £55
```

## Month-start message format (1st of each month)

```
📅 March complete — finance reset done.

Feb allowance: £1,000 loaded, £843 spent  ✓  £157 unspent
Biggest category: Shopping £298

April allowance pot loaded with £1,000. Let me know if you want to adjust the monthly amount or alert thresholds.
```

## Guidelines

- Always fetch fresh data from Google Sheets before answering finance questions
- Never store raw transaction data (merchant names etc.) — only aggregate totals in state files
- If derived balance looks implausible (e.g. loaded > £2,000 or remaining negative by large amount), flag it
- Spending categories are all main-account card payments — a useful proxy for allowance spending but not precise attribution
- If `GOOGLE_SHEETS_SA_KEY` or `MONZO_SHEET_ID` are missing/empty, tell the user the credentials haven't been configured yet
