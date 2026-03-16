# Proposal Respond

Handles /approve and /reject commands from Telegram.

## On /approve YYYY-MM-DD-description

1. Move file from proposals/pending/ to proposals/approved/
   (After implementation, move to proposals/implemented/)
2. Commit and push: `git add . && git commit -m "Approve: description" && git push origin main`
3. Reply via Telegram: "✅ Approved. Send `/claude implement proposals/approved/YYYY-MM-DD-description.md` when ready."

## On /reject YYYY-MM-DD-description

1. Move file to proposals/rejected/
2. Commit and push: `git add . && git commit -m "Reject: description" && git push origin main`
3. Reply via Telegram: "❌ Rejected and archived."

## Important
Only act on commands coming from your authorised Telegram chat ID.
Never approve or reject without an explicit command from the user.
