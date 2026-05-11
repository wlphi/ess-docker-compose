# Matrix Server - Docker Compose Setup

A self-hosted Matrix server stack with modern OIDC authentication, web clients, optional video calling, messaging bridges, and observability.

## What's Included

### Core (always on)

- [Synapse](https://github.com/element-hq/synapse) — Matrix homeserver
- [Matrix Authentication Service (MAS)](https://github.com/element-hq/matrix-authentication-service) — OIDC-based authentication (replaces legacy password auth)
- [Element Web](https://github.com/element-hq/element-web) — Web client
- [Ketesa](https://github.com/etkecc/ketesa) — Admin dashboard (user/room management via Synapse Admin API)
- [synapse_auto_compressor](https://github.com/matrix-org/rust-synapse-compress-state) — Continuous state-group compression to reduce DB bloat
- [PostgreSQL 16](https://www.postgresql.org/) — Database
- [Caddy](https://caddyserver.com/) — Reverse proxy with automatic HTTPS

### Optional: FluffyChat (`--profile fluffychat`)

- [FluffyChat](https://fluffychat.im/) — Alternative Matrix web client with a friendly UI
  - Also registers FluffyChat as an OIDC client in MAS, which fixes the cross-signing reset "continue" button

### Optional: Element Call (`--profile element-call`)

- [LiveKit](https://livekit.io/) — WebRTC SFU media server (self-hosted, media stays on your server)
- [lk-jwt-service](https://github.com/element-hq/lk-jwt-service) — LiveKit token issuer
- [Element Call](https://github.com/element-hq/element-call) — Self-hosted video/voice calling frontend

### Optional: Messaging Bridges

Always available (start with the stack, set up via `setup-bridges.sh`):
- [mautrix-whatsapp](https://github.com/mautrix/whatsapp) — WhatsApp bridge (Go megabridge)
- [mautrix-signal](https://github.com/mautrix/signal) — Signal bridge (Go megabridge)
- [mautrix-telegram](https://github.com/mautrix/telegram) — Telegram bridge (requires API credentials)
- [mautrix-discord](https://github.com/mautrix/discord) — Discord bridge (Go megabridge)
- [mautrix-slack](https://github.com/mautrix/slack) — Slack bridge (Go megabridge — Megaslack)

Optional (`--profile hookshot`):
- [matrix-hookshot](https://github.com/matrix-org/matrix-hookshot) — GitHub, GitLab, JIRA, RSS, and generic webhook integrations

### Optional: Monitoring (`--profile monitoring`)

- [Prometheus](https://prometheus.io/) — Metrics collection (scrapes Synapse at `:9000/metrics`)
- [Grafana](https://grafana.com/) — Dashboard visualization (Synapse dashboard pre-provisioned)

### Optional: Upstream OIDC

- [Authelia](https://www.authelia.com/) — SSO / identity provider with 2FA (`--profile authelia`)
- Any OIDC-compliant provider — Authentik, Keycloak, Zitadel, etc. (no extra containers)

## Quick Start

Simple production deployment — four prompts, everything else is automatic:

```bash
./quickstart.sh
```

Asks for: your domain, a Let's Encrypt email, whether to enable Element Call, and whether to allow open registration. Generates all secrets and configs, starts the stack. Monitoring is always enabled.

Advanced deployment — local testing, SSO options, multi-machine setups, optional bridges and monitoring:

```bash
./deploy.sh
```

Bridges are set up separately after the core stack is running:

```bash
./setup-bridges.sh
```

## Architecture

```text
Browser
  |
Caddy (HTTPS, Let's Encrypt)
  |
  +-- matrix.example.com  -->  Synapse :8008
  |     /.well-known       -->  (served inline by Caddy)
  |     /login, /logout    -->  MAS :8080
  +-- auth.example.com    -->  MAS :8080
  +-- element.example.com -->  Element Web :80
  +-- chat.example.com    -->  FluffyChat :80        (optional)
  +-- admin.example.com   -->  Ketesa :8080
  +-- monitoring.example.com --> Grafana :3000       (optional)
  +-- call.example.com    -->  Element Call :8080    (optional)
  +-- rtc.example.com     -->  lk-jwt-service :8080  (optional)
                               LiveKit :7880          (optional)
```

All services communicate over an internal Docker network. The database is not exposed.

## Deployment Options

Simple production — single machine, Let's Encrypt, four prompts:

```bash
./quickstart.sh
```

Advanced deployment — three modes via interactive menu:

```bash
./deploy.sh
```

| Mode | Description |
| --- | --- |
| Local testing | Self-signed certs, `*.example.test` domains, `/etc/hosts` entries |
| Production (single-server) | Let's Encrypt, all services on one machine |
| Production (distributed) | Caddy / Authelia / Matrix on separate hosts, generates `caddy/Caddyfile.production` |

SSO options (prompted during `deploy.sh`):

1. None — MAS handles passwords directly
2. Authelia — full SSO with 2FA via `--profile authelia`
3. Other OIDC — Authentik, Keycloak, Zitadel, or any OIDC-compliant provider (no extra containers)

## Element Call

When enabled, all three components are self-hosted. Media streams never leave your server (they route through your LiveKit SFU). The Element Call frontend is served from your own `call.` subdomain.

Required open ports in addition to 80 and 443:

- TCP 7881 (WebRTC signaling)
- UDP 50100–50200 (media streams)

## Bridges

`setup-bridges.sh` configures WhatsApp, Signal, Discord, and Slack automatically. Telegram requires API credentials from [my.telegram.org](https://my.telegram.org) — add them to `.env` before running:

```bash
TELEGRAM_API_ID=your_id
TELEGRAM_API_HASH=your_hash
```

All bridges use Go megabridge implementations (Discord, Slack, WhatsApp, Signal) or the current Python bridge (Telegram). Bridges use double puppet support (messages appear from your actual Matrix user, not a bridge bot) and have encryption disabled for compatibility with MAS.

See [BRIDGE_SETUP_GUIDE.md](BRIDGE_SETUP_GUIDE.md) for details, including Discord, Slack, and matrix-hookshot setup.

## Monitoring

When the `monitoring` profile is enabled, Prometheus scrapes Synapse metrics every 15 seconds and Grafana is provisioned with:
- A Prometheus datasource pointing to the internal `prometheus:9090` endpoint
- The official [Synapse dashboard (ID 10046)](https://grafana.com/grafana/dashboards/10046) downloaded at deploy time

Synapse exposes metrics at `:9000/metrics` via a separate `metrics.yaml` config file loaded alongside `homeserver.yaml` (Synapse directory config mode).

## Database Maintenance

`synapse_auto_compressor` runs continuously alongside Postgres and compresses the `state_groups_state` table — the primary source of Synapse database bloat. It requires no configuration and runs automatically whenever Postgres is healthy.

## Synapse Extensions

Add Python packages to `synapse/requirements.txt` (one per line) to install them into the Synapse image at build time — useful for storage providers, LDAP modules, or custom auth handlers. An empty file is a no-op.

## Air-gapped / Custom Registry

`deploy.sh` optionally prefixes all image references with a custom registry URL (for internal mirrors or air-gapped environments) and optionally switches Redis, PostgreSQL, and Caddy to hardened variants from [dhi.io](https://dhi.io). Both settings are written to `.env` and picked up automatically by Docker Compose.

## Requirements

- Docker and Docker Compose v2
- A domain with DNS control
- Ports 80 and 443 accessible from the internet
- For Element Call: ports 7881/TCP and 50100–50200/UDP open

## Common Operations

```bash
# Status
docker compose ps

# Logs
docker compose logs -f [service]

# Restart a service
docker compose restart synapse

# Update all images
docker compose pull && docker compose up -d

# Bridge logs
docker compose logs mautrix-whatsapp
docker compose logs mautrix-discord

# Monitoring
docker compose --profile monitoring logs -f prometheus
docker compose --profile monitoring logs -f grafana
```

## Data Directories

```text
postgres/data/    database (back this up)
synapse/data/     media store, signing keys
mas/data/         MAS sessions
.env              all secrets and domain config
```

Backup:

```bash
tar -czf matrix-backup-$(date +%Y%m%d).tar.gz postgres/data synapse/data mas/data .env
```

## Documentation

- [SETUP.md](SETUP.md) — manual configuration reference
- [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md) — production checklist and hardening
- [BRIDGE_SETUP_GUIDE.md](BRIDGE_SETUP_GUIDE.md) — bridge configuration (including Discord, Slack, hookshot)
- [BUGFIXES.md](BUGFIXES.md) — known issues and their solutions
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) — common commands

## License

- Synapse: Apache 2.0
- Matrix Authentication Service: Apache 2.0
- Element Web / Element Call: Apache 2.0
- Ketesa: MIT
- FluffyChat: AGPL 3.0
- PostgreSQL: PostgreSQL License
- Caddy: Apache 2.0
- LiveKit: Apache 2.0
- Prometheus: Apache 2.0
- Grafana: AGPL 3.0
