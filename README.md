# Matrix Server - Docker Compose Setup

A complete, production-ready Matrix server stack with modern authentication and web client.

## What's Included

- **Synapse** - Matrix homeserver
- **Matrix Authentication Service (MAS)** - Modern OIDC-based authentication
- **Element Web** - Web client interface
- **Element Admin** - Admin dashboard
- **PostgreSQL** - Database backend
- **Caddy** - Reverse proxy with automatic HTTPS

## Features

- Clean template-based configuration
- Optional upstream OIDC integration (Authelia, Keycloak, etc.)
- Separate or combined deployment options
- Comprehensive documentation
- Production-ready security defaults

## Quick Start

1. **Copy templates and configure:**
   ```bash
   cp templates/docker-compose.yml .
   cp templates/.env.template .env
   cp templates/homeserver.yaml synapse/config/
   cp templates/mas-config.yaml mas/config/
   cp templates/element-config.json element/config/
   ```

2. **Follow the setup guide:**

   See **[SETUP.md](SETUP.md)** for complete step-by-step instructions including:
   - Secret generation
   - Configuration placeholders
   - DNS setup
   - Reverse proxy configuration
   - First user creation
   - Troubleshooting

3. **Start the stack:**
   ```bash
   docker compose up -d
   ```

## Architecture

```
Internet (HTTPS)
    ↓
Caddy Reverse Proxy
    ↓
┌─────────────────────────────────────────┐
│  Matrix Stack                           │
│  ┌──────────┬──────────┬──────────┐    │
│  │ Element  │ Synapse  │   MAS    │    │
│  │   Web    │  :8008   │  :8080   │    │
│  └──────────┴─────┬────┴─────┬────┘    │
│                   │          │          │
│              ┌────▼──────────▼────┐    │
│              │   PostgreSQL       │    │
│              └────────────────────┘    │
└─────────────────────────────────────────┘
```

## Documentation

- **[SETUP.md](SETUP.md)** - Complete setup guide with all configuration details
- **templates/** - Clean configuration templates for all services

## Authentication Options

### MAS Only (Default)
- Built-in authentication via Matrix Authentication Service
- User accounts managed within Matrix
- Simpler setup, fewer dependencies

### With Upstream OIDC (Optional)
- Integrate with existing identity providers (Authelia, Keycloak, etc.)
- Centralized authentication across services
- Single Sign-On (SSO) support

See [SETUP.md](SETUP.md) Step 5 for OIDC configuration.

## Configuration Templates

The `templates/` directory contains:

- `docker-compose.yml` - Service orchestration
- `.env.template` - Environment variables with secret generation guidance
- `homeserver.yaml` - Synapse configuration
- `mas-config.yaml` - MAS configuration with optional OIDC
- `element-config.json` - Element Web client configuration
- `Caddyfile` - Reverse proxy configuration
- `authelia-client.yml` - Example OIDC client config for Authelia

All templates use `{{PLACEHOLDER}}` format for easy find-and-replace.

## Deployment Scenarios

### Single Server
Run everything (Matrix + Caddy) on one machine.

### Multi-Server
- Matrix stack on dedicated server
- Caddy reverse proxy on separate edge server
- Optional: Authelia on separate authentication server

See [SETUP.md](SETUP.md) Step 7 for details.

## Requirements

- Docker and Docker Compose
- Domain name with DNS configured
- Ports 80, 443 accessible (for HTTPS/certificates)

## Common Operations

```bash
# Check service status
docker compose ps

# View logs
docker compose logs -f

# Restart services
docker compose restart

# Stop all services
docker compose down

# Update images
docker compose pull
docker compose up -d
```

## Security

- HTTPS enforced via Caddy with automatic Let's Encrypt certificates
- Strong secret generation required (see SETUP.md Step 2)
- Database passwords must be synchronized across configs
- Admin interface access should be restricted by IP

See [SETUP.md](SETUP.md) for security considerations and hardening.

## Backup

Essential data directories:
```
postgres/data/    - Database
synapse/data/     - Synapse media and state
mas/data/         - MAS sessions
.env              - Secrets and configuration
```

Backup command:
```bash
tar -czf matrix-backup-$(date +%Y%m%d).tar.gz \
  postgres/data \
  synapse/data \
  mas/data \
  .env
```

## Support

- **Matrix Synapse**: https://github.com/element-hq/synapse
- **MAS**: https://github.com/element-hq/matrix-authentication-service
- **Element Web**: https://github.com/element-hq/element-web
- **Setup Issues**: See [SETUP.md](SETUP.md) Troubleshooting section

## License

This setup uses the following open-source components:
- Matrix Synapse: Apache 2.0
- Matrix Authentication Service: Apache 2.0
- Element Web: Apache 2.0
- PostgreSQL: PostgreSQL License
- Caddy: Apache 2.0
