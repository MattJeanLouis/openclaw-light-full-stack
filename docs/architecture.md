# Architecture

## Service Diagram

```
  External Traffic                    Docker Compose Network (internal)
 ─────────────────                   ──────────────────────────────────

                                     ┌─────────────────────────────────────────────┐
                                     │                                             │
  Browser / App ────┐                │  ┌───────────┐      ┌───────────────────┐   │
                    │                │  │           │      │                   │   │
  WhatsApp  ────────┤   Tailscale    │  │  Caddy    │      │    OpenClaw       │   │
  Discord   ────────┤── Cloudflare ──┼──│  :80/:443 │─────►│    Gateway        │   │
  Telegram  ────────┤   or LAN       │  │  (proxy)  │      │    :18789         │   │
  Slack     ────────┤                │  └───────────┘      │                   │   │
                    │                │         │            └──────┬──────┬─────┘   │
  API clients ──────┘                │         │                   │      │         │
                                     │         │     ┌─────────────┘      │         │
                                     │         │     │                    │         │
                                     │         │     ▼                    ▼         │
                                     │         │  ┌──────────┐    ┌────────────┐   │
                                     │         │  │ LiteLLM  │    │ PostgreSQL │   │
                                     │         │  │ Proxy    │    │ + pgvector │   │
                                     │         │  │ :4000    │    │ :5432      │   │
                                     │         │  └────┬─────┘    └────────────┘   │
                                     │         │       │                           │
                                     └─────────┼───────┼───────────────────────────┘
                                               │       │
                                               │       ▼
                                               │    AI Providers
                                               │    ├── OpenAI
                                               │    ├── Anthropic
                                               │    ├── Google Gemini
                                               │    └── 100+ others
                                               │
                                          Optional:
                                          ├── Cloudflare Tunnel (cloudflared)
                                          ├── Diun (image update notifications)
                                          └── rclone (Google Drive backup)
```

## Compose Profiles

| Profile | Service | Purpose | Required Config |
|---------|---------|---------|-----------------|
| *(always on)* | `postgres` | Database with pgvector | `POSTGRES_PASSWORD` |
| *(always on)* | `litellm` | AI model proxy | `LITELLM_MASTER_KEY`, provider API keys |
| *(always on)* | `openclaw` | Gateway + messaging | `OPENCLAW_GATEWAY_TOKEN` |
| `proxy` | `caddy` | Reverse proxy, auto HTTPS | `DOMAIN` |
| `tunnel` | `cloudflared` | Cloudflare Tunnel | `CLOUDFLARE_TUNNEL_TOKEN` |
| `notify` | `diun` | Image update notifications | — |
| `backup` | `backup` (rclone) | Scheduled cloud backup | `config/rclone.conf` |

## Data Flow

1. **Inbound request** arrives from a browser, messaging channel, or API client.
2. If the `proxy` profile is active, **Caddy** terminates TLS and forwards to OpenClaw.
   Otherwise, traffic hits OpenClaw directly on port 18789.
3. **OpenClaw gateway** processes the request: authenticates, manages conversation
   state, selects tools, and determines which model to call.
4. OpenClaw sends the AI completion request to **LiteLLM** at `http://litellm:4000/v1`.
5. **LiteLLM** routes the request to the configured upstream **AI provider**
   (OpenAI, Anthropic, Google, etc.), handling retries, caching, and key rotation.
6. The AI response flows back through LiteLLM to OpenClaw.
7. OpenClaw persists conversation data in **PostgreSQL** (via LiteLLM's DB connection),
   and stores agent/session state in its local data volume.
8. The response is delivered to the user via the original channel.

## Security Boundaries

### Internal-only services (no host port)

- **PostgreSQL** — accessible only on the `internal` Docker network. No port
  binding to the host. Connection string is only known to LiteLLM.
- **LiteLLM** — accessible only on the `internal` Docker network. Protected
  by `LITELLM_MASTER_KEY`. OpenClaw connects via internal DNS (`litellm:4000`).

### Host-exposed services

- **OpenClaw gateway** — exposed on `OPENCLAW_PORT` (default 18789). Protected
  by `OPENCLAW_GATEWAY_TOKEN`.
- **Caddy** (profile `proxy`) — exposed on ports 80 and 443. Provides TLS
  termination. Should only be enabled when a real domain is configured.

### Secrets management

- All secrets live in `.env`, which is gitignored.
- Three generated secrets: gateway token (64 hex chars), Postgres password
  (64 hex chars), LiteLLM master key (`sk-` + 64 hex chars).
- `config/rclone.conf` (Google Drive OAuth tokens) is also gitignored.
- API provider keys are passed as environment variables, never written to
  config files on disk.

### Network recommendations

- **LAN only**: Default. Gateway is reachable from the local network.
- **Tailscale**: Install Tailscale on the host for encrypted remote access
  without opening ports.
- **Cloudflare Tunnel**: Enable the `tunnel` profile for zero-trust access
  through Cloudflare's network.
- **Public internet**: Use Caddy (`proxy` profile) with a real domain for
  automatic HTTPS. Never expose the raw gateway port to the internet.
