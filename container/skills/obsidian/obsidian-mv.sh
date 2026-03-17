#!/usr/bin/env bash
# Usage: obsidian-mv.sh <old-path> <new-path>
# Paths are relative to the vault root.
# Moves a note and updates all wikilink references in the vault.
set -euo pipefail

OLD="$1"
NEW="$2"
VAULT="${OBSIDIAN_VAULT:-/workspace/extra/obsidian-vault}"

OLD_NAME=$(basename "$OLD" .md)
NEW_NAME=$(basename "$NEW" .md)

# Move the file
mkdir -p "$(dirname "$VAULT/$NEW")"
mv "$VAULT/$OLD" "$VAULT/$NEW"

# Update wikilinks across the vault
find "$VAULT" -name "*.md" -exec sed -i "s/\[\[$OLD_NAME\]\]/[[$NEW_NAME]]/g" {} +
find "$VAULT" -name "*.md" -exec sed -i "s/\[\[$OLD_NAME|/[[$NEW_NAME|/g" {} +

echo "Moved: $OLD → $NEW"
echo "Updated wikilinks: [[${OLD_NAME}]] → [[${NEW_NAME}]]"
