#!/usr/bin/env bash
# NanoClaw disaster recovery backup
# Encrypts critical state and uploads to OneDrive. Retains 7 daily backups.
set -euo pipefail

LOG_FILE="/root/nanoclaw/logs/backup.log"
TIMESTAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)
BACKUP_NAME="nanoclaw-backup-${TIMESTAMP}.tar.gz.gpg"
TMPDIR=$(mktemp -d)

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"; }
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

log "Starting backup: $BACKUP_NAME"

# ── Load environment ──────────────────────────────────────────────────────────
ENV_FILE="/root/nanoclaw/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  log "ERROR: .env not found at $ENV_FILE"
  exit 1
fi
set -a; source "$ENV_FILE"; set +a

if [[ -z "${BACKUP_PASSPHRASE:-}" ]]; then
  log "ERROR: BACKUP_PASSPHRASE not set in .env"
  exit 1
fi

# ── Create archive ────────────────────────────────────────────────────────────
ARCHIVE="${TMPDIR}/backup.tar.gz"
log "Archiving critical files..."

tar -czf "$ARCHIVE" \
  --ignore-failed-read \
  /root/nanoclaw/.env \
  /root/nanoclaw/store/messages.db \
  /root/nanoclaw/groups/ \
  /root/.config/nanoclaw/ \
  /root/nanoclaw/data/sessions/ \
  /root/nanoclaw-config/.env \
  2>/dev/null || true

ARCHIVE_SIZE=$(du -sh "$ARCHIVE" | cut -f1)
log "Archive size: $ARCHIVE_SIZE"

# ── Encrypt ───────────────────────────────────────────────────────────────────
ENCRYPTED="${TMPDIR}/${BACKUP_NAME}"
log "Encrypting..."
gpg --batch --yes \
  --passphrase "$BACKUP_PASSPHRASE" \
  --symmetric \
  --cipher-algo AES256 \
  --output "$ENCRYPTED" \
  "$ARCHIVE"

# ── Get OneDrive access token ─────────────────────────────────────────────────
log "Getting OneDrive access token..."
TOKEN_RESPONSE=$(curl -s -X POST \
  "https://login.microsoftonline.com/common/oauth2/v2.0/token" \
  -d "grant_type=refresh_token" \
  -d "client_id=${ORION_ONEDRIVE_CLIENT_ID}" \
  -d "client_secret=${ORION_ONEDRIVE_CLIENT_SECRET}" \
  --data-urlencode "refresh_token=${ORION_ONEDRIVE_REFRESH_TOKEN}" \
  -d "scope=https://graph.microsoft.com/Files.ReadWrite")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
if [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]]; then
  log "ERROR: Failed to get OneDrive token: $(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error // "unknown"')"
  exit 1
fi

# ── Upload to OneDrive ────────────────────────────────────────────────────────
log "Uploading to OneDrive..."
UPLOAD_RESPONSE=$(curl -s -X PUT \
  "https://graph.microsoft.com/v1.0/me/drive/root:/nanoclaw-backups/${BACKUP_NAME}:/content" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@$ENCRYPTED")

UPLOAD_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id // empty')
if [[ -z "$UPLOAD_ID" ]]; then
  log "ERROR: Upload failed: $(echo "$UPLOAD_RESPONSE" | jq -r '.error.message // "unknown"')"
  exit 1
fi
log "Upload successful (id: $UPLOAD_ID)"

# ── Prune old backups (keep 7 most recent) ────────────────────────────────────
log "Pruning old backups..."
LIST_RESPONSE=$(curl -s \
  "https://graph.microsoft.com/v1.0/me/drive/root:/nanoclaw-backups:/children?\$select=id,name,lastModifiedDateTime&\$orderby=lastModifiedDateTime+desc" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

# Delete any beyond the 7 most recent
echo "$LIST_RESPONSE" | jq -r '.value[7:][].id' | while read -r FILE_ID; do
  FILE_NAME=$(echo "$LIST_RESPONSE" | jq -r --arg id "$FILE_ID" '.value[] | select(.id == $id) | .name')
  log "Deleting old backup: $FILE_NAME"
  curl -s -X DELETE \
    "https://graph.microsoft.com/v1.0/me/drive/items/${FILE_ID}" \
    -H "Authorization: Bearer $ACCESS_TOKEN"
done

log "Backup complete."
