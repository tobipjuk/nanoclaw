---
name: outlook
description: Read Tobi's Outlook email via Microsoft Graph API — list unread inbox, read messages, search, or cross-reference the Scheduled folder against the Personal calendar. Use whenever asked about emails, inbox, scheduled items, or calendar gaps.
allowed-tools: Bash(curl*)
---

# Outlook (Microsoft Graph API)

Credentials are injected as environment variables — never log or expose them:
- `MICROSOFT_CLIENT_ID`
- `MICROSOFT_REFRESH_TOKEN`
- `MICROSOFT_USER_EMAIL`

## Get an access token

```bash
TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/common/oauth2/v2.0/token" \
  -d "grant_type=refresh_token" \
  -d "client_id=$MICROSOFT_CLIENT_ID" \
  --data-urlencode "refresh_token=$MICROSOFT_REFRESH_TOKEN" \
  -d "scope=https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/Calendars.Read" \
  | jq -r '.access_token')
```

## Known folder IDs

| Folder | ID |
|--------|----|
| Inbox | `AQMkADAwATM3ZmYAZS1kYzhlLTBhNzktMDACLTAwCgAuAAADYk92BkgEeUeUqzBrFircawEAzi6ftpS1V06t_yfsuiJn0wAAAgEMAAAA` |
| Scheduled (Inbox subfolder) | `AQMkADAwATM3ZmYAZS1kYzhlLTBhNzktMDACLTAwCgAuAAADYk92BkgEeUeUqzBrFircawEAzi6ftpS1V06t_yfsuiJn0wAI4-60IQAAAA==` |

## List messages in a folder

```bash
FOLDER_ID="<folder id>"

curl -s "https://graph.microsoft.com/v1.0/me/mailFolders/${FOLDER_ID}/messages?\$top=50&\$select=subject,receivedDateTime,from,bodyPreview" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.value[] | {subject, from: .from.emailAddress.address, received: .receivedDateTime[:10], preview: .bodyPreview}]'
```

## List unread inbox emails

```bash
INBOX_ID="AQMkADAwATM3ZmYAZS1kYzhlLTBhNzktMDACLTAwCgAuAAADYk92BkgEeUeUqzBrFircawEAzi6ftpS1V06t_yfsuiJn0wAAAgEMAAAA"

curl -s "https://graph.microsoft.com/v1.0/me/mailFolders/${INBOX_ID}/messages?\$filter=isRead eq false&\$select=id,subject,from,receivedDateTime,bodyPreview&\$top=20&\$orderby=receivedDateTime desc" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.value[] | {id, from: .from.emailAddress.address, received: .receivedDateTime[:10], subject, preview: .bodyPreview}]'
```

## Read a specific email (full body)

```bash
MESSAGE_ID="<message id>"

curl -s "https://graph.microsoft.com/v1.0/me/messages/${MESSAGE_ID}?\$select=subject,from,receivedDateTime,body" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{subject, from: .from.emailAddress.address, received: .receivedDateTime, body: (.body.content | gsub("<[^>]+>"; "") | gsub("\\s+"; " "))}'
```

## Search inbox

```bash
curl -s "https://graph.microsoft.com/v1.0/me/messages?\$search=\"SEARCH_TERM\"&\$select=id,subject,from,receivedDateTime,bodyPreview&\$top=10" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.value[] | {from: .from.emailAddress.address, subject, received: .receivedDateTime[:10], preview: .bodyPreview}]'
```

## Cross-reference Scheduled folder against Personal calendar

When asked whether items in the Scheduled folder have corresponding calendar entries:

**Step 1 — get Scheduled emails with previews:**
```bash
SCHEDULED_ID="AQMkADAwATM3ZmYAZS1kYzhlLTBhNzktMDACLTAwCgAuAAADYk92BkgEeUeUqzBrFircawEAzi6ftpS1V06t_yfsuiJn0wAI4-60IQAAAA=="

curl -s "https://graph.microsoft.com/v1.0/me/mailFolders/${SCHEDULED_ID}/messages?\$top=50&\$select=id,subject,receivedDateTime,from,bodyPreview" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.value[] | {id, subject, from: .from.emailAddress.address, received: .receivedDateTime[:10], preview: .bodyPreview}]'
```

**Step 2 — if bodyPreview is CSS-heavy, fetch the full body:**
```bash
curl -s "https://graph.microsoft.com/v1.0/me/messages/MESSAGE_ID?\$select=subject,body" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{subject, body: (.body.content | gsub("<[^>]+>"; "") | gsub("\\s+"; " ") | .[0:800])}'
```

**Step 3 — get Personal calendar (90-day window):**
```bash
PERSONAL_ID="AQMkADAwATM3ZmYAZS1kYzhlLTBhNzktMDACLTAwCgBGAAADYk92BkgEeUeUqzBrFircawcAzi6ftpS1V06t_yfsuiJn0wAAAgEGAAAAzi6ftpS1V06t_yfsuiJn0wAAAlKHAAAA"
START=$(date -u +%Y-%m-%dT00:00:00Z)
END=$(date -u -d '+90 days' +%Y-%m-%dT00:00:00Z)

curl -s "https://graph.microsoft.com/v1.0/me/calendars/${PERSONAL_ID}/calendarView?\$orderby=start/dateTime&startDateTime=${START}&endDateTime=${END}&\$select=subject,start,end,isAllDay" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Prefer: outlook.timezone="Europe/London"' \
  | jq '[.value[] | {subject, start: .start.dateTime[:16], isAllDay}]'
```

**Step 4 — compare and report:**
Extract the appointment date/time from each email (from bodyPreview or full body). Check whether a Personal calendar event exists on that date. Report missing entries clearly.

## Guidelines

- Read-only — never send, delete, or move emails
- When cross-referencing Scheduled vs calendar: **only check Personal calendar, never Family calendar**
- If bodyPreview is CSS-heavy (e.g. dojo.app), fetch full body and strip HTML
- Omit emails that clearly aren't personal appointments (newsletters, receipts without dates, automated system alerts)
- Summarise emails concisely — sender, subject, key action if any
