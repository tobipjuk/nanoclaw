---
name: calendar
description: Read Tobi's Outlook calendar via Microsoft Graph API — get today's events, events for a date range, or check availability. Use whenever asked about schedule, meetings, what's on, or free time. Always shows both Personal and Family calendars as separate sections.
allowed-tools: Bash(curl*)
---

# Calendar (Microsoft Graph API)

Credentials are injected as environment variables — never log or expose them:
- `MICROSOFT_CLIENT_ID`
- `MICROSOFT_REFRESH_TOKEN`
- `MICROSOFT_USER_EMAIL`

All times are returned in Europe/London timezone.

## Calendars

Always query **both** calendars and present them as separate sections in your reply:

| Calendar | ID |
|----------|----|
| Personal (Calendar) | `AQMkADAwATM3ZmYAZS1kYzhlLTBhNzktMDACLTAwCgBGAAADYk92BkgEeUeUqzBrFircawcAzi6ftpS1V06t_yfsuiJn0wAAAgEGAAAAzi6ftpS1V06t_yfsuiJn0wAAAlKHAAAA` |
| Family | `AQMkADAwATM3ZmYAZS1kYzhlLTBhNzktMDACLTAwCgBGAAADYk92BkgEeUeUqzBrFircawcAzi6ftpS1V06t_yfsuiJn0wAAAgEGAAAAzi6ftpS1V06t_yfsuiJn0wAIHe-u0AAAAA==` |

## Get an access token

```bash
TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/common/oauth2/v2.0/token" \
  -d "grant_type=refresh_token" \
  -d "client_id=$MICROSOFT_CLIENT_ID" \
  --data-urlencode "refresh_token=$MICROSOFT_REFRESH_TOKEN" \
  -d "scope=https://graph.microsoft.com/Calendars.Read" \
  | jq -r '.access_token')
```

## Get events for a date range (both calendars)

Run this for each calendar ID, then present results in two labelled sections:

```bash
PERSONAL_ID="AQMkADAwATM3ZmYAZS1kYzhlLTBhNzktMDACLTAwCgBGAAADYk92BkgEeUeUqzBrFircawcAzi6ftpS1V06t_yfsuiJn0wAAAgEGAAAAzi6ftpS1V06t_yfsuiJn0wAAAlKHAAAA"
FAMILY_ID="AQMkADAwATM3ZmYAZS1kYzhlLTBhNzktMDACLTAwCgBGAAADYk92BkgEeUeUqzBrFircawcAzi6ftpS1V06t_yfsuiJn0wAAAgEGAAAAzi6ftpS1V06t_yfsuiJn0wAIHe-u0AAAAA=="

START=$(date -u +%Y-%m-%dT00:00:00Z)
END=$(date -u -d '+1 day' +%Y-%m-%dT00:00:00Z)  # adjust range as needed

# Personal calendar
curl -s "https://graph.microsoft.com/v1.0/me/calendars/${PERSONAL_ID}/calendarView?\$orderby=start/dateTime&startDateTime=${START}&endDateTime=${END}&\$select=subject,start,end,isAllDay,location" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Prefer: outlook.timezone=\"Europe/London\"" \
  | jq '[.value[] | {subject, start: .start.dateTime[:16], end: .end.dateTime[:16], isAllDay, location: .location.displayName}]'

# Family calendar
curl -s "https://graph.microsoft.com/v1.0/me/calendars/${FAMILY_ID}/calendarView?\$orderby=start/dateTime&startDateTime=${START}&endDateTime=${END}&\$select=subject,start,end,isAllDay,location" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Prefer: outlook.timezone=\"Europe/London\"" \
  | jq '[.value[] | {subject, start: .start.dateTime[:16], end: .end.dateTime[:16], isAllDay, location: .location.displayName}]'
```

## Date range examples

```bash
# Today
START=$(date -u +%Y-%m-%dT00:00:00Z)
END=$(date -u -d '+1 day' +%Y-%m-%dT00:00:00Z)

# This week
START=$(date -u +%Y-%m-%dT00:00:00Z)
END=$(date -u -d '+7 days' +%Y-%m-%dT00:00:00Z)

# Specific day
START="2026-03-20T00:00:00Z"
END="2026-03-21T00:00:00Z"
```

## Guidelines

- Read-only — never create, update, or delete events
- Always query both calendars and present as two sections: **Personal** and **Family**
- Always present times in Europe/London (handled by the Prefer header)
- For all-day events, omit the time
- If asked "am I free?" check both calendars for conflicts
- Omit location if empty
