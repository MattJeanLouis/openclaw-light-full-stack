# CLAUDE.md — OpenClaw Self-Host Stack

This is the companion guide for Claude Code. It describes every file, config key,
make target, and diagnostic procedure in this repo so you can modify the stack
directly and confidently.

## Repository Layout

```
.
├── .env.example          # Template — copied to .env by setup
├── .env                  # SECRETS — never committed (gitignored)
├── docker-compose.yml    # All services: core + profile-gated
├── Makefile              # Every operator command
├── config/
│   ├── openclaw.json     # OpenClaw gateway configuration (JSONC)
│   ├── litellm.yaml      # LiteLLM proxy model routing
│   ├── Caddyfile         # Reverse proxy (profile: proxy)
│   └── rclone.conf       # Google Drive backup creds (gitignored)
├── scripts/
│   ├── setup.sh          # Interactive first-run wizard
│   ├── update.sh         # Pull + progressive restart + rollback
│   ├── backup.sh         # DB dump + config snapshot + rclone sync
│   ├── restore.sh        # Interactive restore from local backup
│   ├── setup-backup.sh   # Configure rclone for Google Drive
│   └── diun-notify.sh    # Diun notification script (writes updates.json)
├── docs/
│   └── architecture.md   # Service diagram, data flow, security
├── .github/
│   ├── workflows/validate.yml  # CI: compose lint, YAML check, file check
│   └── renovate.json           # Automated Docker image updates
├── CLAUDE.md             # This file
└── README.md             # Human-facing quick start
```

---

## Phase 1 — Installation

### Quick path

```bash
git clone <repo-url> && cd openclaw-light-full-stack
make setup
```

`make setup` runs `scripts/setup.sh`, which does:

1. Checks prerequisites (Docker, Compose v2, running daemon).
2. Detects architecture (ARM64 / x86_64).
3. Copies `.env.example` to `.env` (asks before overwriting).
4. Generates cryptographic secrets via `openssl rand -hex 32`:
   - `OPENCLAW_GATEWAY_TOKEN`
   - `POSTGRES_PASSWORD`
   - `LITELLM_MASTER_KEY` (prefixed `sk-`)
5. Prompts for an OpenAI API key (optional; more can be added later).
6. Offers optional profiles: Cloudflare Tunnel, Diun notifications.
7. Pulls container images with `docker compose pull`.
8. Starts services with `docker compose up -d`.
9. Waits up to 60 s for healthchecks.
10. Prints gateway URL, token, and next-step commands.

### Manual alternative

```bash
cp .env.example .env
# Edit .env: set OPENCLAW_GATEWAY_TOKEN, POSTGRES_PASSWORD, LITELLM_MASTER_KEY
# Set at least one AI provider key (OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.)
docker compose pull
docker compose up -d
```

---

## Phase 2 — Configuration

### .env file (secrets + tunables)

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `OPENCLAW_GATEWAY_TOKEN` | Yes | `change-me` | Auth token for gateway API |
| `LITELLM_MASTER_KEY` | Yes | `sk-change-me` | LiteLLM admin API key |
| `POSTGRES_PASSWORD` | Yes | `change-me` | PostgreSQL password |
| `OPENAI_API_KEY` | At least one provider | — | OpenAI API key |
| `ANTHROPIC_API_KEY` | — | — | Anthropic API key |
| `GEMINI_API_KEY` | — | — | Google Gemini API key |
| `OPENCLAW_IMAGE` | — | `ghcr.io/openclaw/openclaw:latest` | Container image override |
| `OPENCLAW_BIND` | — | `lan` | Bind mode: `lan`, `loopback`, `0.0.0.0` |
| `OPENCLAW_PORT` | — | `18789` | Host port for gateway |
| `POSTGRES_USER` | — | `openclaw` | PostgreSQL user |
| `POSTGRES_DB` | — | `litellm` | PostgreSQL database name |
| `COMPOSE_PROFILES` | — | (empty) | Comma-separated: `proxy`, `tunnel`, `notify`, `backup` |
| `OPENCLAW_ALLOW_INSECURE_PRIVATE_WS` | — | (empty) | Allow insecure WebSocket on private networks |
| `CLOUDFLARE_TUNNEL_TOKEN` | If profile `tunnel` | — | Cloudflare Tunnel token |
| `DOMAIN` | If profile `proxy` | `localhost` | Domain for Caddy HTTPS |
| `DIUN_WATCH_SCHEDULE` | — | `0 */6 * * *` | Diun update check cron schedule |
| `RCLONE_REMOTE` | — | `gdrive` | rclone remote name for backup sync |

### config/openclaw.json — OpenClaw gateway config

This is JSONC (comments allowed). Mounted read-only into the container at
`/home/node/.openclaw/openclaw.json`.

Key paths and what they control:

| Key | Type | Purpose |
|-----|------|---------|
| `gateway.mode` | `"local"` | Gateway operation mode. Keep `"local"` for self-host. |
| `gateway.bind` | `"lan"` / `"loopback"` | Network bind. Overridden by `OPENCLAW_BIND` env var in compose. |
| `agents.defaults.model.primary` | string | Default model ID, e.g. `"litellm/gpt-4o-mini"`. Prefix with `litellm/` for LiteLLM-routed models. |
| `agents.defaults.model.fallbacks` | string[] | Ordered fallback model IDs. |
| `agents.defaults.models` | object | Map of model ID to display metadata (`alias`). |
| `agents.defaults.sandbox` | object | Sandbox configuration for agent tools. |
| `agents.defaults.cliBackends` | string[] | CLI backend list. |
| `channels.*` | object | Per-channel configuration (WhatsApp, Discord, Telegram, etc.). |
| `models.mode` | `"merge"` / `"replace"` | How to combine provider models with built-ins. Use `"merge"`. |
| `models.providers.<name>.baseUrl` | string | Provider API endpoint. For LiteLLM: `"http://litellm:4000/v1"`. |
| `models.providers.<name>.apiKey` | string | API key. Use `"from-env"` to read from container env. |
| `models.providers.<name>.api` | string | API format: `"openai-responses"`, `"openai-chat"`, etc. |
| `models.providers.<name>.models` | array | Model definitions with `id`, `name`, `reasoning`, `input`, `cost`, `contextWindow`, `maxTokens`. |
| `tools.*` | object | Tool configuration and permissions. |

#### Common task: Change default model

Edit `config/openclaw.json`:
```jsonc
{
  agents: {
    defaults: {
      model: {
        primary: "litellm/claude-sonnet-4-20250514",   // change this
        fallbacks: ["litellm/gpt-4o"],                  // and/or this
      },
    },
  },
}
```
Then `make restart`.

#### Common task: Add an AI provider (e.g. Anthropic)

1. Add the key to `.env`:
   ```
   ANTHROPIC_API_KEY=sk-ant-...
   ```

2. Add model entries to `config/litellm.yaml` under `model_list`:
   ```yaml
   - model_name: claude-sonnet-4-20250514
     litellm_params:
       model: anthropic/claude-sonnet-4-20250514
       api_key: os.environ/ANTHROPIC_API_KEY
   ```

3. Add the model to `config/openclaw.json` under `models.providers.litellm.models`:
   ```jsonc
   {
     id: "claude-sonnet-4-20250514",
     name: "Claude Sonnet 4 (via LiteLLM)",
     reasoning: true,
     input: ["text", "image"],
     cost: { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 },
     contextWindow: 200000,
     maxTokens: 16384,
   }
   ```

4. Optionally update `agents.defaults.models` with an alias.
5. `make restart` to apply.

#### Common task: Add a messaging channel

Channels are configured at runtime via the OpenClaw CLI, not in config files:

```bash
make cli
# Then inside the CLI, run channel-specific setup commands.
# Check status afterward:
make channels-status
```

Supported channels: WhatsApp (web), Discord, Telegram, Slack, Signal, iMessage,
and extensions (MS Teams, Matrix, Zalo, voice-call).

#### Common task: Enable Compose profiles

Edit `.env`:
```
COMPOSE_PROFILES=proxy,tunnel,notify,backup
```
Then `make restart` (or `make down && make up`).

Profiles:
- `proxy` — Caddy reverse proxy with automatic HTTPS (requires `DOMAIN`)
- `tunnel` — Cloudflare Tunnel zero-trust access (requires `CLOUDFLARE_TUNNEL_TOKEN`)
- `notify` — Diun container image update notifications
- `backup` — rclone scheduled backup service

#### Common task: Set budget / cost limits

Use LiteLLM's budget features. Edit `config/litellm.yaml`:
```yaml
litellm_settings:
  max_budget: 100.0        # USD monthly budget
  budget_duration: "monthly"
```
Or manage via LiteLLM API from inside the Docker network:
```bash
docker compose exec openclaw curl -s http://litellm:4000/budget/info -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

### config/litellm.yaml — LiteLLM proxy config

Mounted read-only into LiteLLM at `/app/config.yaml`.

| Key | Purpose |
|-----|---------|
| `model_list` | Array of model definitions. Each has `model_name` (alias) and `litellm_params` (provider, key). |
| `litellm_settings.drop_params` | Drop unsupported params instead of erroring. Keep `true`. |
| `litellm_settings.cache` | Enable response caching. |
| `litellm_settings.cache_params.type` | Cache backend: `"local"` (in-memory) or `"redis"`. |
| `general_settings.master_key` | Admin key, read from env. |
| `general_settings.database_url` | PostgreSQL connection, read from env. |

Full reference: https://docs.litellm.ai/docs/proxy/configs

### config/Caddyfile — Reverse proxy

Only active when `proxy` profile is enabled. Uses the `DOMAIN` env var (default
`localhost`). Proxies all traffic to `openclaw:18789`.

### config/rclone.conf — Backup destination (gitignored)

Created by `make setup-backup`. Contains Google Drive OAuth credentials.
Never committed.

### Full configuration references

- OpenClaw: https://docs.openclaw.ai/gateway/configuration-reference
- LiteLLM: https://docs.litellm.ai/docs/proxy/configs

---

## Phase 3 — Operations

### Make commands

| Command | What it does |
|---------|-------------|
| `make setup` | Run interactive setup wizard (first-time) |
| `make setup-backup` | Configure Google Drive rclone backup |
| `make up` | Start all services (`docker compose up -d`) |
| `make down` | Stop all services (`docker compose down`) |
| `make restart` | Restart all services |
| `make logs` | Follow all service logs |
| `make logs-openclaw` | Follow OpenClaw logs only |
| `make logs-litellm` | Follow LiteLLM logs only |
| `make status` | Show service status + healthchecks |
| `make update` | Pull new images, progressive restart, rollback on failure |
| `make backup` | Dump DB + snapshot configs + sync to Google Drive |
| `make restore` | Interactive restore from local backup |
| `make cli` | Open OpenClaw CLI inside the container |
| `make config-get KEY=...` | Read an OpenClaw config value |
| `make config-set KEY=... VALUE=...` | Set an OpenClaw config value |
| `make channels-status` | Probe channel connection status |
| `make clean` | Remove containers, volumes, and backups (DESTRUCTIVE, confirms) |
| `make help` | List all targets |

### Diagnostics

#### Service won't start

```bash
make status                  # Check which service is unhealthy
make logs                    # Full logs
docker compose logs <svc>    # Single service logs
docker compose ps -a         # Include stopped containers
```

#### OpenClaw issues

```bash
make cli                     # Then run: doctor
# Or directly:
docker compose exec openclaw openclaw doctor

# Health endpoint:
curl http://localhost:18789/healthz
```

#### LiteLLM not routing models

```bash
make logs-litellm            # Check for API key errors
# Verify config is mounted:
docker compose exec litellm cat /app/config.yaml
# Test model directly (from inside Docker network):
docker compose exec openclaw curl -s http://litellm:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

#### PostgreSQL issues

```bash
docker compose exec postgres pg_isready -U openclaw
docker compose logs postgres
# Connect directly:
docker compose exec postgres psql -U openclaw -d litellm
```

#### SD card / disk health (Raspberry Pi)

```bash
df -h                        # Check disk usage
iostat -x 1 3                # I/O stats
# PostgreSQL WAL can grow; monitor pg_data volume size.
```

### Update strategy

`make update` runs `scripts/update.sh`:

1. Creates a pre-update backup (DB dump + configs).
2. Records current image digests for rollback.
3. Pulls latest images (`docker compose pull`).
4. Restarts services progressively: postgres -> litellm -> openclaw -> profile services.
5. Waits for healthchecks (60 s timeout).
6. On failure, offers interactive rollback to previous images.

For pinned versions instead of `latest`, set `OPENCLAW_IMAGE` in `.env` or
edit image tags directly in `docker-compose.yml`.

### Backup strategy

`make backup` runs `scripts/backup.sh`:

1. Dumps PostgreSQL with `pg_dumpall` (gzipped).
2. Copies `.env`, `openclaw.json`, `litellm.yaml`.
3. Copies OpenClaw agent data and identity from the container.
4. Keeps the last 7 local backups (auto-prunes older ones).
5. If `config/rclone.conf` exists, syncs `backups/` to Google Drive via rclone.

Backups are stored in `backups/<timestamp>/`. Restore with `make restore`.

To set up Google Drive sync: `make setup-backup`.

---

## Security Notes

- `.env` is gitignored and must never be committed. It contains all secrets.
- `config/rclone.conf` is gitignored. Contains Google Drive OAuth tokens.
- All three secrets (`OPENCLAW_GATEWAY_TOKEN`, `LITELLM_MASTER_KEY`,
  `POSTGRES_PASSWORD`) are generated as 64-char hex strings by setup.
- PostgreSQL is on an internal Docker network only — no host port exposed.
- LiteLLM is on the internal network only — no host port exposed.
- Only OpenClaw's gateway port (default 18789) is exposed to the host.
- When using Caddy (`proxy` profile), ports 80/443 are also exposed.
- Use strong, unique tokens. Rotate by editing `.env` and running `make restart`.
- For remote access, prefer Cloudflare Tunnel (`tunnel` profile) or Tailscale
  over exposing ports directly.
