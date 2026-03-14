# Proposal Notify

When a new proposal is written to proposals/pending/, notify the user
via Telegram with the full proposal contents and approval options.

## Message Format

Send this to the user's Telegram:

---
📋 **New Proposal**: YYYY-MM-DD-description

**What**: [what field]
**Why**: [why field]
**How**: [how field]
**Risk**: [risk field]

Reply with:
✅ `/approve YYYY-MM-DD-description` to approve
❌ `/reject YYYY-MM-DD-description` to reject
---

Do not take any action until a reply is received.
