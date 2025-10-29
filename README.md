# Matrix Communication Stack with HTTPS & SSO

Complete self-hosted Matrix homeserver with optional Authelia SSO, automated HTTPS, and messaging bridges.

## What's Included

- **Matrix Synapse** - Homeserver
- **Element Web** - Web client
- **Matrix Authentication Service (MAS)** - OIDC authentication
- **Authelia** (Optional) - SSO with 2FA support
- **Caddy** - Automatic HTTPS (Let's Encrypt for production, self-signed for local)
- **PostgreSQL** - Database backend
- **Redis** (Optional) - Authelia session storage
- **Bridges** - Telegram, WhatsApp, Signal integration (requires post-deployment setup)

## Quick Start - Local Testing

### 1. Configure Hosts File

Add to `/etc/hosts`:

```bash
127.0.0.1  matrix.example.test element.example.test auth.example.test authelia.example.test
::1        matrix.example.test element.example.test auth.example.test authelia.example.test
```

**Note:** Both IPv4 and IPv6 entries are required. See [BUGFIXES.md](BUGFIXES.md) Issue #10 for details.

### 2. Run Deployment Script

```bash
chmod +x deploy.sh
./deploy.sh
```

Choose:
- **Deployment type**: Local
- **Include Authelia?**: Yes (for SSO with 2FA) or No (simpler, MAS-only auth)

The script will:
- Generate all secrets and passwords
- Configure all services
- Start Docker stack
- Display access URLs and credentials

**⚠️ Save the admin password shown at the end!**

### 3. Access Services

| Service | URL |
|---------|-----|
| Element Web | https://element.example.test |
| Matrix API | https://matrix.example.test |
| MAS Auth | https://auth.example.test |
| Authelia SSO | https://authelia.example.test |

**Note:** You'll see security warnings for self-signed certificates. Accept them to proceed (this is expected for local testing).

### 4. Sign In

1. Open https://element.example.test
2. Click "Sign In"
3. Login with credentials from deployment script
4. Set up 2FA if using Authelia

### 5. Configure Bridges (Optional)

```bash
./setup-bridges.sh
```

Then message the bridge bots in Element to link your accounts:
- Telegram: `@telegrambot:matrix.example.test`
- WhatsApp: `@whatsappbot:matrix.example.test`
- Signal: `@signalbot:matrix.example.test`

See [BRIDGE_SETUP_GUIDE.md](BRIDGE_SETUP_GUIDE.md) for details.

## Production Deployment

See [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md) for:
- Single-machine and multi-machine architectures
- Let's Encrypt automatic HTTPS
- Security hardening
- Backup strategies
- Monitoring and maintenance

**Deploy command:**
```bash
# With Authelia
docker compose -f docker-compose.production.yml --profile authelia up -d

# Without Authelia
docker compose -f docker-compose.production.yml up -d
```

## Authentication Options

### With Authelia (Recommended)
- SSO with 2FA (TOTP)
- Centralized user management
- Works with LDAP or flat files

### Without Authelia (Simpler)
- MAS handles authentication directly
- No upstream OAuth provider
- Fewer dependencies

## Architecture

```
Browser (HTTPS)
    ↓
Caddy (Port 443) - Automatic HTTPS
    ↓
┌─────────┬──────────┬─────────┬──────────┐
│ Element │ Synapse  │   MAS   │ Authelia │
│   Web   │  :8008   │  :8080  │  :9091   │
└─────────┴────┬─────┴────┬────┴────┬─────┘
               │          │         │
               │          │    ┌────▼────┐
               │          │    │  Redis  │
               │          │    └─────────┘
               │          │
           ┌───▼──────────▼─────┐
           │    PostgreSQL      │
           └────────────────────┘

Bridges (Internal Network):
├── Telegram (mautrix-telegram)
├── WhatsApp (mautrix-whatsapp)
└── Signal (mautrix-signal)
```

## Documentation

- **[PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md)** - Production deployment guide
- **[BRIDGE_SETUP_GUIDE.md](BRIDGE_SETUP_GUIDE.md)** - Bridge configuration explained
- **[BUGFIXES.md](BUGFIXES.md)** - Critical issues and solutions (10 documented issues)
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Common operations reference

## Data Directories

All persistent data stored in:

```
postgres/data/     - Database
synapse/data/      - Synapse data & media
mas/data/          - MAS session data
bridges/*/config/  - Bridge configurations & sessions
authelia/config/   - Authelia config & users
caddy/data/        - SSL certificates (production)
```

**These directories are in `.gitignore` to protect sensitive data.**

## Common Commands

```bash
# Check services
docker compose ps

# View logs
docker compose logs -f

# View specific service logs
docker compose logs synapse --tail 50

# Restart service
docker compose restart synapse

# Stop everything
docker compose down

# Start fresh (⚠️ deletes all data)
docker compose down -v
rm -rf postgres/data synapse/data mas/data
```

## Troubleshooting

### Services Won't Start After Update

If PostgreSQL password mismatch occurs (see BUGFIXES.md Issue #9):

```bash
# Stop services
docker compose stop

# Remove old PostgreSQL data
sudo rm -rf postgres/data

# Re-run deployment
./deploy.sh
```

### Element Can't Connect

Check MAS delegation:
```bash
curl -k https://matrix.example.test/.well-known/matrix/client
```

Should return authentication issuer URL.

### Bridges Not Working

1. Run `./setup-bridges.sh` if not done already
2. Check bridge logs: `docker compose logs mautrix-telegram`
3. See [BRIDGE_SETUP_GUIDE.md](BRIDGE_SETUP_GUIDE.md) for chicken-and-egg problem explanation

## Backup

```bash
tar -czf matrix-backup-$(date +%Y%m%d).tar.gz \
  postgres/data \
  synapse/data \
  mas/data \
  authelia/config \
  bridges/*/config \
  .env
```

## Security Notes

### For Local Testing
- Self-signed certificates (expected security warnings)
- Default test domain (example.test)
- Generated passwords (save from deploy script output)

### For Production
- Use real domain names
- Let's Encrypt automatic HTTPS
- Change all default passwords
- Enable 2FA in Authelia
- Configure firewall rules
- Regular updates and backups

See [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md) Security Hardening section.

## Deployment Variants

| Mode | Certificates | DNS | Authelia | Command |
|------|--------------|-----|----------|---------|
| Local | Self-signed | /etc/hosts | Optional | `./deploy.sh` → Local |
| Production | Let's Encrypt | Real DNS | Optional | `./deploy.sh` → Production |

## Scripts

- **deploy.sh** - Main deployment automation
- **setup-bridges.sh** - Bridge configuration automation

## Resources

- [Matrix Synapse Docs](https://element-hq.github.io/synapse/)
- [MAS Docs](https://element-hq.github.io/matrix-authentication-service/)
- [Authelia Docs](https://www.authelia.com/)
- [Mautrix Docs](https://docs.mau.fi/)

## License

Individual components retain their licenses:
- Matrix Synapse: Apache 2.0
- Element: Apache 2.0
- MAS: Apache 2.0
- Authelia: Apache 2.0
- Mautrix bridges: AGPL-3.0
