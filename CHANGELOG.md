# Changelog

All notable changes to NanoClaw will be documented in this file.

## Unreleased

- **fix(whoop):** Whoop API v2 returns records ascending (oldest first), so `limit=1` without a date filter returned the oldest record ever. Now fetches the last 5 records from a 3-day window and reads the last item to get the most recent data.

## [1.2.0](https://github.com/qwibitai/nanoclaw/compare/v1.1.6...v1.2.0)

[BREAKING] WhatsApp removed from core, now a skill. Run `/add-whatsapp` to re-add (existing auth/groups preserved).
- **fix:** Prevent scheduled tasks from executing twice when container runtime exceeds poll interval (#138, #669)
