# Matrix Communication Stack with HTTPS & SSO

A complete, self-hosted Matrix homeserver setup with Authelia SSO authentication, automated HTTPS, and messaging bridges.

## What's Included

- **Matrix Synapse** - The homeserver
- **Element Web** - Web client interface
- **Matrix Authentication Service (MAS)** - Modern authentication with OIDC
- **Authelia** - SSO provider with 2FA
- **Caddy** - Automatic HTTPS with self-signed certificates for local testing
- **PostgreSQL** - Database backend
- **Redis** - Session storage
- **Bridges** - Telegram, WhatsApp, and Signal integration (pre-configured)
- **Element-X** - Mobile client support (iOS & Android)

## Deployment Modes

This setup supports two deployment modes:

### 🏠 Local Testing (All-in-One)
All services run on a single machine via `docker-compose.yml`. Perfect for development and testing.
- **Guide**: Follow the Quick Start below

### 🏢 Production (Distributed)
Services distributed across 3 machines for security and scalability:
- Machine 1: Caddy (SSL termination)
- Machine 2: Authelia (SSO)
- Machine 3: Matrix stack (Synapse, Element, MAS, Bridges)

- **Guide**: See [PRODUCTION.md](PRODUCTION.md)

## Quick Start (Local Testing with HTTPS)

### 1. Update Your Hosts File

Add these entries to `/etc/hosts`:

```bash
sudo nano /etc/hosts
```

Add the following lines:
```
127.0.0.1  matrix.example.test
127.0.0.1  element.example.test
127.0.0.1  auth.example.test
127.0.0.1  authelia.example.test
```

**Note:** We use `example.test` (not `.localhost`) to avoid [public suffix list](https://publicsuffix.org/) issues with Authelia cookie domains. See [BUGFIXES.md](BUGFIXES.md) for details.

### 2. Run the Automated Deployment Script

```bash
chmod +x deploy.sh
./deploy.sh
```

The script will automatically:
- ✅ Generate all secure secrets (passwords, keys, tokens)
- ✅ Create RSA keys for Authelia and MAS
- ✅ Generate and hash a random admin password
- ✅ Configure all services with HTTPS
- ✅ Start the entire Docker stack
- ✅ Display your admin password and access URLs

**⚠️ IMPORTANT:** Save the admin password shown at the end!

### 3. Access Services (via HTTPS)

| Service | URL | Purpose |
|---------|-----|---------|
| Element Web | https://element.example.test | Main web interface |
| Matrix API | https://matrix.example.test | Homeserver API |
| MAS | https://auth.example.test | Authentication service |
| Authelia | https://authelia.example.test | SSO portal |
| Caddy Admin | http://localhost:2019 | Reverse proxy admin |

**Note:** You'll see a security warning about self-signed certificates. This is expected for local development. Click "Advanced" → "Proceed to site".

### 4. Sign In

1. Go to **https://element.example.test**
2. Accept the self-signed certificate warning
3. Click "Sign In"
4. You'll be redirected through MAS → Authelia for SSO
5. Log in with:
   - Username: `admin`
   - Password: (shown by deploy.sh)
6. Set up 2FA (Time-based OTP) using your authenticator app if required
7. Complete registration
8. Start chatting!

## Documentation

- **[SETUP.md](SETUP.md)** - Comprehensive setup guide with all details
- **[BUGFIXES.md](BUGFIXES.md)** - Critical bugfixes and lessons learned (undocumented issues)
- **[CHECKLIST.md](CHECKLIST.md)** - Step-by-step checklist to track progress
- **[PRODUCTION.md](PRODUCTION.md)** - Production deployment guide (distributed setup)
- **[requirements.md](requirements.md)** - Original requirements
- **[research.md](research.md)** - Research resources

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `setup-synapse.sh` | Generate Synapse configuration |
| `setup-bridges.sh` | Generate bridge configurations |
| `validate-setup.sh` | Validate configuration before starting |

## Architecture

```
                    Browser (HTTPS)
                          │
                          ▼
         ┌────────────────────────────────────┐
         │         Caddy (Port 443)           │
         │  Automatic HTTPS with self-signed  │
         │        certificates                │
         └───┬──────────┬─────────┬──────────┘
             │          │         │
    element.│  matrix. │  auth.  │ authelia.
    example. │ example. │example. │ example.
    test     │  test    │ test    │  test
             │          │         │
      ┌──────▼───┐  ┌──▼────┐ ┌─▼────┐ ┌────▼─────┐
      │ Element  │  │Synapse│ │ MAS  │ │ Authelia │
      │   Web    │  │  :8008│ │ :8080│ │   :9091  │
      └──────────┘  └───┬───┘ └──┬───┘ └────┬─────┘
                        │        │          │
                        │        │     ┌────▼────┐
                        │        │     │  Redis  │
                        │        │     └─────────┘
                        │        │
                    ┌───▼────────▼────┐
                    │   PostgreSQL    │
                    │ (synapse, mas,  │
                    │    authelia)    │
                    └─────────────────┘

Bridges (Internal Network):
├── Telegram  (mautrix-telegram)
├── WhatsApp  (mautrix-whatsapp)
└── Signal    (mautrix-signal)
```

## Configuration Files

### Auto-Generated by deploy.sh
- `.env` - Environment variables and all secrets (auto-generated)
- `authelia_private.pem` - Authelia RSA private key
- `mas-signing.key` - MAS signing key
- `synapse/data/homeserver.yaml` - Synapse configuration
- `authelia/config/configuration.yml` - Authelia SSO configuration
- `authelia/config/users_database.yml` - Default admin user
- `mas/config/config.yaml` - MAS configuration with Authelia integration
- `caddy/Caddyfile` - Reverse proxy configuration (pre-created)

### Pre-configured
- `docker-compose.yml` - Service orchestration
- `caddy/Caddyfile` - HTTPS termination and routing
- `postgres/init/01-init-databases.sql` - Database initialization

## Exposed Ports

| Port | Service | Purpose |
|------|---------|---------|
| 443  | Caddy | HTTPS for all services |
| 80   | Caddy | HTTP (redirects to HTTPS) |
| 2019 | Caddy | Admin API |

All other services (Synapse, Element, MAS, Authelia) are only exposed internally within the Docker network and accessed via Caddy.

## Data Persistence

All data is stored in local directories:

```
postgres/data/     - Database
synapse/data/      - Synapse data & media
mas/data/          - MAS data
bridges/*/config/  - Bridge configurations
authelia/config/   - Authelia config & users
```

**Important:** These directories are in `.gitignore` to protect sensitive data.

## Troubleshooting

### Quick Diagnostics

```bash
# Check all services
docker compose ps

# View logs
docker compose logs -f

# Restart a service
docker compose restart synapse

# Stop everything
docker compose down

# Start fresh (⚠️ deletes all data)
docker compose down -v
rm -rf postgres/data synapse/data
```

### Common Issues

1. **Port already in use** - Edit `docker-compose.yml` and change port mappings
2. **Permission denied** - Check directory permissions
3. **Service won't start** - Check logs with `docker compose logs service-name`
4. **Can't login** - Verify Authelia user configuration and password hash

See [SETUP.md](SETUP.md) for detailed troubleshooting.

## Security

⚠️ **This setup is for local testing by default**

For production use:
- Change all passwords and secrets in `.env`
- Set up HTTPS with a reverse proxy (Caddy/nginx)
- Use real domain names
- Configure firewall
- Enable regular backups
- Review all configuration files
- Keep containers updated

See the "Security Notes" section in [SETUP.md](SETUP.md).

## Backup

Essential directories to backup:
```bash
tar -czf matrix-backup-$(date +%Y%m%d).tar.gz \
  postgres/data \
  synapse/data \
  mas/data \
  authelia/config \
  bridges/*/config
```

## Useful Commands

```bash
# View real-time logs
docker compose logs -f

# Restart specific service
docker compose restart synapse

# Access Postgres shell
docker compose exec postgres psql -U synapse

# Generate Authelia password hash
docker run authelia/authelia:latest authelia crypto hash generate argon2 --password 'yourpassword'

# Generate secure secret
openssl rand -base64 32

# Check disk usage
docker compose exec postgres du -sh /var/lib/postgresql/data
```

## Resources

- [Matrix.org](https://matrix.org/) - Matrix protocol
- [Synapse Docs](https://matrix-org.github.io/synapse/latest/)
- [Element Docs](https://element.io/help)
- [MAS Docs](https://element-hq.github.io/matrix-authentication-service/)
- [Authelia Docs](https://www.authelia.com/)
- [mautrix Docs](https://docs.mau.fi/)

## Getting Help

1. Check the logs: `docker compose logs -f`
2. Read [SETUP.md](SETUP.md) for detailed instructions
3. Use [CHECKLIST.md](CHECKLIST.md) to ensure all steps are complete
4. Run `./validate-setup.sh` to check configuration
5. Check the official documentation links above

## License

This configuration is provided as-is for your use. Individual components have their own licenses:
- Matrix Synapse: Apache 2.0
- Element: Apache 2.0
- MAS: Apache 2.0
- Authelia: Apache 2.0
- mautrix bridges: AGPL-3.0

## Contributing

Feel free to customize this setup for your needs. If you find issues or improvements, document them for your own reference.
