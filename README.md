# openclaw-light-full-stack

A complete, self-hosted AI assistant stack built on [OpenClaw](https://openclaw.ai). Clone, setup, run.

Works on any Docker-capable machine: Raspberry Pi, home server, cloud VM, or laptop.

## What You Get

- **OpenClaw** gateway with multi-channel messaging (WhatsApp, Discord, Telegram, Slack, and more)
- **LiteLLM** proxy for unified access to OpenAI, Anthropic, Google, and 100+ AI providers
- **PostgreSQL + pgvector** for persistent storage and vector search
- **API access** on your local network (default port 18789)
- **Optional services**: Caddy reverse proxy (automatic HTTPS), Cloudflare Tunnel, Diun update notifications, rclone Google Drive backups

## Quick Start

```bash
git clone https://github.com/openclaw/openclaw-light-full-stack.git
cd openclaw-light-full-stack
make setup
```

The setup wizard generates secrets, asks for your AI provider key, and starts everything.

**Alternative — Claude Code guided setup:** Open this repo in Claude Code and ask it to set up the stack. It will read `CLAUDE.md` and configure everything for you.

## Commands

| Command | Description |
|---------|-------------|
| `make setup` | Interactive first-run setup wizard |
| `make up` | Start all services |
| `make down` | Stop all services |
| `make restart` | Restart all services |
| `make status` | Show service status and health |
| `make logs` | Follow all service logs |
| `make update` | Pull latest images and restart safely |
| `make backup` | Backup database and configs |
| `make restore` | Restore from a backup |
| `make cli` | Open the OpenClaw CLI |
| `make channels-status` | Check messaging channel connections |
| `make help` | Show all available commands |

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │            Docker Compose               │
                    │                                         │
 Browser/App ──────►│  ┌──────────┐    ┌──────────┐          │
                    │  │  Caddy   │───►│ OpenClaw │          │──► AI Providers
 WhatsApp ─────────►│  │ (proxy)  │    │ Gateway  │──┐       │    (OpenAI,
 Discord ──────────►│  └──────────┘    └────┬─────┘  │       │     Anthropic,
 Telegram ─────────►│                       │        │       │     Google, ...)
                    │                       ▼        ▼       │
                    │                  ┌──────────┐ ┌──────┐ │
                    │                  │ LiteLLM  │ │  PG  │ │
                    │                  │  Proxy   │ │pgvec │ │
                    │                  └──────────┘ └──────┘ │
                    │                                         │
                    │  Optional: Cloudflare Tunnel, Diun,     │
                    │            rclone backup                │
                    └─────────────────────────────────────────┘
```

## Configuration Files

| File | Purpose |
|------|---------|
| `.env` | Secrets and environment variables (gitignored) |
| `config/openclaw.json` | OpenClaw gateway settings, model routing, channels |
| `config/litellm.yaml` | LiteLLM model list and proxy settings |
| `config/Caddyfile` | Caddy reverse proxy rules |
| `config/rclone.conf` | Google Drive backup credentials (gitignored) |

See `CLAUDE.md` for a detailed reference of every configuration key.

## Requirements

- Docker + Docker Compose v2
- 2+ GB RAM
- ARM64 (Raspberry Pi 4/5, Apple Silicon) or x86_64
- At least one AI provider API key

## License

MIT
