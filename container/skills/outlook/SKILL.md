---
name: outlook
description: Read Tobi's Outlook inbox via Microsoft Graph API — list unread emails, read a specific email, search inbox. Use whenever asked about emails, inbox, or specific messages.
allowed-tools: Bash(curl*)
---

# Outlook (Microsoft Graph API)

Credentials are injected as environment variables — never log or expose them:
- `MICROSOFT_CLIENT_ID`
- `MICROSOFT_CLIENT_SECRET`
- `MICROSOFT_REFRESH_TOKEN`
- `MICROSOFT_USER_EMAIL`

## Get an access token

All Graph API calls need a Bearer token. Fetch one first and store it:

```bash
TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/common/oauth2/v1.0/token" \
  -d "grant_type=refresh_token" \
  -d "client_id=$MICROSOFT_CLIENT_ID" \
  -d "client_secret=$MICROSOFT_CLIENT_SECRET" \
  -d "refresh_token=$MICROSOFT_REFRESH_TOKEN" \
  -d "scope=https://graph.microsoft.com/Mail.ReadWrite" \
  | jq -r '.access_token')
```

## List unread inbox emails

```bash
curl -s "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?\$filter=isRead eq false&\$select=id,subject,from,receivedDateTime,bodyPreview&\$top=20&\$orderby=receivedDateTime desc" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.value[] | {
      id,
      from: .from.emailAddress.address,
      from_name: .from.emailAddress.name,
      received: .receivedDateTime,
      subject,
      preview: .bodyPreview
    }]'
```

## Read a specific email (full body)

```bash
curl -s "https://graph.microsoft.com/v1.0/me/messages/MESSAGE_ID?\$select=subject,from,receivedDateTime,body" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{subject, from: .from.emailAddress.address, received: .receivedDateTime, body: .body.content}' \
  | sed 's/<[^>]*>//g'
```

## Search inbox

```bash
curl -s "https://graph.microsoft.com/v1.0/me/messages?\$search=\"SEARCH_TERM\"&\$select=id,subject,from,receivedDateTime,bodyPreview&\$top=10" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.value[] | {from: .from.emailAddress.address, subject, received: .receivedDateTime, preview: .bodyPreview}]'
```

## Mark an email as read

```bash
curl -s -X PATCH "https://graph.microsoft.com/v1.0/me/messages/MESSAGE_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"isRead": true}'
```

## Guidelines

- Read-only by default — never send, delete, or move emails unless Tobi explicitly asks
- Always fetch a fresh token at the start of each session
- Summarise emails concisely — sender, subject, key action if any
- For long threads, read the latest message first and offer to retrieve the full thread
