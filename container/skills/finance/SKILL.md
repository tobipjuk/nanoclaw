---
name: finance
description: Read Tobi's Monzo transaction data from Google Sheets and provide personal finance insights — main account balance, allowance spending by category, weekly check-ins, and proactive alerts. Use whenever asked about money, spending, balance, allowance, or transactions.
allowed-tools: Bash(curl*), Bash(jq*), Bash(cat*), Bash(echo*), Bash(date*), Bash(mkdir*), Bash(cp*)
---

# Finance (Monzo via Google Sheets)

Reads Tobi's Monzo transaction data from Google Sheets (read-only). Never writes to the sheet.

Credentials are injected as environment variables — never log or expose them:
- `GOOGLE_SHEETS_SA_KEY` — Service account JSON key (base64-encoded)
- `MONZO_SHEET_ID` — Google Sheet ID

Config and state are stored in `/workspace/extra/nanoclaw-config/finance/`:
- `config.json` — allowance amount and alert thresholds
- `state/YYYY-MM.json` — monthly state (anchor, alerts fired)

## Financial Structure

```
Salary → Monzo Main Account
  → Fixed Expenses Pot  (bills — covered by Direct Debits, excluded from allowance tracking)
  → Repayments Pot      (loan repayments — excluded from allowance tracking)
  → Remainder stays in main account for personal spending (PRIMARY FOCUS)
```

Card payments come directly from the main account. Loan repayments go out as Faster Payments (categorised as Transfers — excluded automatically). Bills are covered by the Fixed Expenses Pot via Direct Debits (excluded automatically).

**Never read the `Joint Account Transactions` tab** — always use `Personal Account Transactions` only.

## Allowance model

The allowance budget is £1,000/month (from config). Spending is tracked from **card payments** and personal peer-to-peer transfers. Excluded: Direct Debits (bills via Fixed Expenses Pot), Instalment loans, Pot transfers (internal), Transfers-category transactions (salary in, loan repayments out), and Income-category transactions.

## Fetch transactions for the current month

Run `monzo-fetch.sh` to get this month's **raw** transactions as JSON:

```bash
bash /home/node/.claude/skills/finance/monzo-fetch.sh
```

Output: JSON array of `{transaction_id, date, time, type, name, category, amount}` for the current month.

The script merges Google Sheets data with any manual CSV supplements in `/workspace/extra/nanoclaw-shared/finance/` (CSV wins on duplicate transaction IDs — used for the March 2026 transition period).

## Get filtered (allowance-relevant) transactions

**Always use `monzo-transactions.sh` for per-transaction queries** (e.g. "show me shopping transactions", "what did I spend on eating out"). It applies the same exclusion filters as `allowance-summary.sh`:

```bash
bash /home/node/.claude/skills/finance/monzo-transactions.sh
```

Or pass a pre-fetched file to avoid re-fetching:

```bash
bash /home/node/.claude/skills/finance/monzo-transactions.sh /tmp/monzo-raw.json
```

Output: filtered JSON array — excludes Pot transfers, Direct Debits, Instalment loans, Transfers-category, and Income-category transactions.

Use `monzo-fetch.sh` directly **only** when all transaction types are needed (e.g. balance anchor calculation).

## Calculate allowance summary

```bash
bash /home/node/.claude/skills/finance/monzo-fetch.sh > /tmp/monzo-raw.json
bash /home/node/.claude/skills/finance/allowance-summary.sh \
  /tmp/monzo-raw.json \
  /workspace/extra/nanoclaw-config/finance/config.json \
  /workspace/extra/nanoclaw-config/finance/state/$(date +%Y-%m).json
```

Output fields:
- `total_spent` — net card payment spend this month
- `allowance_remaining` — £1,000 − total_spent
- `spend_by_category` — breakdown by Monzo category
- `projected_spend` / `projected_remaining` — pace-based projection
- `current_balance` — main account balance (only if anchor is set in state file)
- `anchor_date` — date the anchor was last set

## Balance anchor

The sheet has no running balance column, so the current main account balance is calculated from an anchor: a known confirmed balance at a specific date, plus the net of all transactions since that date.

**Anchor is stored in the state file:**
```json
"anchor": { "date": "2026-03-21", "balance": 1234.56 }
```

**When to update the anchor:**
- When Tobi replies to the Friday balance request with a figure
- When Tobi says "my balance is £X" or "I have £X in my account" in any conversation
- Store immediately: read state file, set `anchor.date` to today, `anchor.balance` to the figure, write back

**How current_balance is calculated:**
`anchor.balance + sum(ALL transaction amounts since anchor.date)`
This includes pot transfers, salary, card payments, direct debits — everything that moves the main account balance.

**If anchor is null or stale (>7 days old):** report `total_spent` and `allowance_remaining` from card payments, but note that balance is unavailable — ask Tobi to confirm his current main account balance.

## Sheet columns

`Transaction ID, Date, Time, Type, Name, Emoji, Category, Amount, Currency, Local amount, Local currency, Notes and #tags, Address, Receipt, Description, Category split`

Key transaction types:
- `Card payment` — personal spending (main category for allowance tracking)
- `Pot transfer` + Name `Fixed Expenses Pot` — bill pot movements (internal, excluded)
- `Pot transfer` + Name `Repayments Pot` — repayment pot movements (internal, excluded)
- `Direct Debit` — bills paid by Fixed Expenses Pot (excluded)
- `Faster payment` category `Transfers` — salary in or loan repayments out (excluded)
- `Faster payment` category `General` etc. — personal bank transfers (included)

## State file format

```json
{
  "month": "2026-03",
  "last_updated": "2026-03-21T17:00:00Z",
  "anchor": { "date": "2026-03-21", "balance": 1234.56 },
  "alerts_fired": ["milestone_100", "milestone_200"]
}
```

`anchor` is `null` until Tobi confirms his balance.
`alerts_fired` tracks which £100 milestones have been sent this month to avoid duplicates.

## Weekly check-in message format

```
📊 Weekly Finance Check-in — w/c 16 Mar

Allowance: £716 remaining of £1,000
▓▓▓▓░░░░░░  28% spent  |  12 days left in March

You're on a good pace — projected to finish the month with ~£400 left.

Spending by category this month:
• Shopping        £143
• Eating out       £85
• Transport        £43
• Entertainment    £35
• General          £22

Notable transactions this week:
• 17 Mar — Amazon £47.20
• 18 Mar — Deliveroo £18.50

Main account balance: £1,234 (as of 14 Mar)

What's your current main account balance? I'll keep it updated.
```

If no anchor is set, omit the balance line and ask for the balance at the end.
Use *bold* (single asterisks) for Telegram. No markdown headings.

## Alert message format (fires at each £100 milestone)

```
💸 Allowance — £200 spent

£800 remaining of £1,000  |  10 Mar  |  21 days left

Spent this month by category:
• Shopping        £143
• Eating out       £57
```

## Month-start message format (1st of each month)

```
📅 March complete — finance reset done.

March: £843 spent of £1,000 budget  ✓  £157 under budget
Biggest category: Shopping £298

April tracking started. What's your current main account balance?
```

## Guidelines

- Always fetch fresh data from Google Sheets before answering finance questions
- Never store raw transaction data (merchant names etc.) — only aggregate totals in state files
- If `current_balance` looks implausible (e.g. negative by a large amount or over £10,000), flag it
- If `GOOGLE_SHEETS_SA_KEY` or `MONZO_SHEET_ID` are missing/empty, tell the user the credentials haven't been configured yet
- March 2026 is a transition month — card payments before ~17 March came from a separate Allowance Pot account and are included via CSV supplements; from April everything flows through the main account directly
