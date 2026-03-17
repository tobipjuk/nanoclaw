---
name: obsidian
description: Read and write notes in Tobi's Obsidian vault. Use for searching, reading, creating, moving, and deleting notes, and for processing the Inbox.
allowed-tools: Bash(find*), Bash(grep*), Bash(cat*), Bash(cp*), Bash(mv*), Bash(rm*), Bash(mkdir*), Bash(git*), Bash(bash*)
---

# Obsidian Vault

Vault path: `/workspace/extra/obsidian-vault`

```bash
VAULT="/workspace/extra/obsidian-vault"
```

## Folder structure

```
Inbox/          ← all raw captures land here (voice notes, quick thoughts)
Notes/
  Work/         ← security, CISO, governance, strategy
  Personal/     ← personal development, health, learning
Maps/           ← Maps of Content (index notes linking related topics)
Projects/       ← one note or subfolder per active project
Resources/
  Orion/        ← Orion/NanoClaw documentation and command reference
Journal/        ← weekly reviews and reflections
Archive/        ← completed projects, dormant notes
  Apple Notes/  ← imported Apple Notes (historical)
  Files/        ← attached media files (historical)
```

**Rules:**
- New captures always go to `Inbox/` — never directly to other folders
- Never create new top-level folders without being asked
- Filename format for inbox items: `YYYY-MM-DD-HH-MM.md`

## Operations

**Search by filename:**
```bash
find "$VAULT" -name "*.md" -iname "*query*"
```

**Search by content:**
```bash
grep -rl "query" "$VAULT" --include="*.md"
```

**Read a note:**
```bash
cat "$VAULT/path/to/note.md"
```

**Create a note:**
```bash
mkdir -p "$VAULT/$(dirname "path/to/note.md")"
cat > "$VAULT/path/to/note.md" << 'EOF'
content here
EOF
```

**Move/rename a note (with wikilink update):**
```bash
bash /workspace/project/container/skills/obsidian/obsidian-mv.sh "old/path.md" "new/path.md"
```

**Delete a note:**
```bash
rm "$VAULT/path/to/note.md"
```

**List Inbox:**
```bash
find "$VAULT/Inbox" -name "*.md" | sort
```

**Count unreviewed inbox items (older than 24h):**
```bash
find "$VAULT/Inbox" -name "*.md" -mmin +1440 | wc -l
```

## After any write operation

After every create, move, or delete, commit and push immediately:

```bash
cd "$VAULT" && git add -A && git commit -m "orion: <short description>" && git push
```

If `git push` fails, surface the error — do not silently swallow it.

## Inbox review workflow (`/inbox`)

1. List all files in `Inbox/` with a one-line summary of each
2. For each note, ask: **expand**, **file**, or **delete**
   - **Expand** — draft a proper note and suggest a destination folder
   - **File** — move directly to the appropriate folder using `obsidian-mv.sh`
   - **Delete** — remove the file
3. Commit and push after all changes are made (one commit for the batch)
