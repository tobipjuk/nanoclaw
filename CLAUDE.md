# NanoClaw

Personal Claude assistant. See [README.md](README.md) for philosophy and setup. See [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for architecture decisions.

## Quick Context

Single Node.js process with skill-based channel system. Channels (WhatsApp, Telegram, Slack, Discord, Gmail) are skills that self-register at startup. Messages route to Claude Agent SDK running in containers (Linux VMs). Each group has isolated filesystem and memory.

## Key Files

| File | Purpose |
|------|---------|
| `src/index.ts` | Orchestrator: state, message loop, agent invocation |
| `src/channels/registry.ts` | Channel registry (self-registration at startup) |
| `src/ipc.ts` | IPC watcher and task processing |
| `src/router.ts` | Message formatting and outbound routing |
| `src/config.ts` | Trigger pattern, paths, intervals |
| `src/container-runner.ts` | Spawns agent containers with mounts |
| `src/task-scheduler.ts` | Runs scheduled tasks |
| `src/db.ts` | SQLite operations |
| `groups/{name}/CLAUDE.md` | Per-group memory (isolated) |
| `container/skills/` | Skills loaded inside agent containers (browser, status, formatting) |

## Skills

Four types of skills exist in NanoClaw. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full taxonomy and guidelines.

- **Feature skills** — merge a `skill/*` branch to add capabilities (e.g. `/add-telegram`, `/add-slack`)
- **Utility skills** — ship code files alongside SKILL.md (e.g. `/claw`)
- **Operational skills** — instruction-only workflows, always on `main` (e.g. `/setup`, `/debug`)
- **Container skills** — loaded inside agent containers at runtime (`container/skills/`)

| Skill | When to Use |
|-------|-------------|
| `/setup` | First-time installation, authentication, service configuration |
| `/customize` | Adding channels, integrations, changing behavior |
| `/debug` | Container issues, logs, troubleshooting |
| `/update-nanoclaw` | Bring upstream NanoClaw updates into a customized install |
| `/qodo-pr-resolver` | Fetch and fix Qodo PR review issues interactively or in batch |
| `/get-qodo-rules` | Load org- and repo-level coding rules from Qodo before code tasks |

## Contributing

Before creating a PR, adding a skill, or preparing any contribution, you MUST read [CONTRIBUTING.md](CONTRIBUTING.md). It covers accepted change types, the four skill types and their guidelines, SKILL.md format rules, PR requirements, and the pre-submission checklist (searching for existing PRs/issues, testing, description format).

## Development

Run commands directly—don't tell the user to run them.

```bash
npm run dev          # Run with hot reload
npm run build        # Compile TypeScript
./container/build.sh # Rebuild agent container
```

Service management:
```bash
# macOS (launchd)
launchctl load ~/Library/LaunchAgents/com.nanoclaw.plist
launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist
launchctl kickstart -k gui/$(id -u)/com.nanoclaw  # restart

# Linux (systemd)
systemctl --user start nanoclaw
systemctl --user stop nanoclaw
systemctl --user restart nanoclaw
```

## Dual Credential Proxy (API vs Claude Max)

At startup, NanoClaw runs two credential proxies:

| Port | Auth mode | Used for |
|------|-----------|----------|
| 3001 (`CREDENTIAL_PROXY_PORT`) | API key | Scheduled tasks |
| 3002 (`CREDENTIAL_PROXY_OAUTH_PORT`) | OAuth / Claude Max | Interactive sessions |

`container-runner.ts` routes based on `isScheduledTask`: scheduled tasks always hit the API key proxy; interactive sessions hit the OAuth proxy (falls back to API key if no OAuth token is set).

To enable: ensure `CLAUDE_CODE_OAUTH_TOKEN` is set in `.env`. Port overrides via env vars `CREDENTIAL_PROXY_PORT` / `CREDENTIAL_PROXY_OAUTH_PORT`.

## Troubleshooting

**WhatsApp not connecting after upgrade:** WhatsApp is now a separate skill, not bundled in core. Run `/add-whatsapp` (or `npx tsx scripts/apply-skill.ts .claude/skills/add-whatsapp && npm run build`) to install it. Existing auth credentials and groups are preserved.

## Container Build Cache

The container buildkit caches the build context aggressively. `--no-cache` alone does NOT invalidate COPY steps — the builder's volume retains stale files. To force a truly clean rebuild, prune the builder then re-run `./container/build.sh`.

## Writable Additional Mounts (vault, git repos)

`container-runner.ts` calls `chownToNodeUser()` then `chmodWritable()` on every writable additional mount before each container start. This ensures:

- Files created by root on the host (e.g. from `git pull` cron jobs) are accessible on the next container run
- Git operations (`git commit`, `git push`) work — git refuses to operate in repos owned by a different user (CVE-2022-24765), so the mount must be owned by uid 1000 (the container's `node` user)

**If git push fails in a container with a "dubious ownership" error**, the vault directory on the host is likely owned by root. Fix with:

```bash
chown -R 1000:1000 /path/to/vault
```

Root retains full access to uid-1000-owned files, so host-side cron pulls and backups are unaffected.

## Per-Group Agent-Runner Source

`container/agent-runner/src/` is copied **once** into `data/sessions/{group}/agent-runner-src/` the first time a group's container runs, and never updated automatically. When you modify `ipc-mcp-stdio.ts` or `index.ts`, you must also sync the change to each group's copy:

```bash
cp container/agent-runner/src/ipc-mcp-stdio.ts data/sessions/{group}/agent-runner-src/
```

The container's entrypoint recompiles on startup, so no container rebuild is needed — just copy and the next run picks it up.
