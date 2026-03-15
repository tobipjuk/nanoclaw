---
name: calendar
description: Read Tobi's Outlook calendar via Microsoft Graph API — get today's events, events for a date range, or check availability. Use whenever asked about schedule, meetings, what's on, or free time.
allowed-tools: Bash(curl*)
---

# Calendar (Microsoft Graph API)

Credentials are injected as environment variables — never log or expose them:
- `MICROSOFT_CLIENT_ID`
- `MICROSOFT_REFRESH_TOKEN`
- `MICROSOFT_USER_EMAIL`

All times are returned in Europe/London timezone.

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

## Get today's events

```bash
START=$(date -u +%Y-%m-%dT00:00:00Z)
END=$(date -u -d '+1 day' +%Y-%m-%dT00:00:00Z)

curl -s "https://graph.microsoft.com/v1.0/me/calendarView?\$orderby=start/dateTime&startDateTime=${START}&endDateTime=${END}&\$select=subject,start,end,isAllDay,location,bodyPreview" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Prefer: outlook.timezone=\"Europe/London\"" \
  | jq '[.value[] | {
      subject,
      start: .start.dateTime[:16],
      end:   .end.dateTime[:16],
      isAllDay,
      location: .location.displayName
    }]'
```

## Get events for a date range

Replace `START` and `END` with ISO dates, e.g. this week:

```bash
START=$(date -u +%Y-%m-%dT00:00:00Z)
END=$(date -u -d '+7 days' +%Y-%m-%dT00:00:00Z)
# ... same curl as above
```

## Check a specific day

```bash
START="2026-03-20T00:00:00Z"
END="2026-03-21T00:00:00Z"
# ... same curl as above
```

## Guidelines

- Read-only — never create, update, or delete events
- Always present times in Europe/London (already handled by the Prefer header)
- For all-day events, omit the time
- If asked "am I free?" check for conflicts in the relevant window and give a direct answer
- Omit location if empty
