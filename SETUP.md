# Matrix Server Setup Guide

This guide will help you set up a complete Matrix stack with:
- **Synapse** - Matrix homeserver
- **Matrix Authentication Service (MAS)** - Modern OIDC-based authentication
- **Element Web** - Web client
- **Element Admin** - Admin interface
- **PostgreSQL** - Database backend
- **Caddy** - Reverse proxy (separate server)
- **Authelia** - Optional upstream OIDC provider (example config included)

## Prerequisites

- Docker and Docker Compose installed
- A domain name (we'll use `example.com` as placeholder)
- DNS records configured:
  - `matrix.example.com` → Your server IP
  - `element.example.com` → Your server IP (or reverse proxy IP)
- If using Authelia: separate Authelia server at `auth.example.com`

## Architecture Overview

```
User → Caddy (reverse proxy) → Synapse/MAS/Element
                                    ↓
                              PostgreSQL
                                    ↓
                          Authelia (optional)
```

## Step 1: Clone and Setup

```bash
git clone <your-repo-url>
cd matrix-docker-compose

# Copy environment template
cp .env.template .env
```

## Step 2: Generate Secrets

You need to generate several secure secrets. **IMPORTANT**: Follow these requirements:

### Database Password
```bash
# Generate a 32-character alphanumeric password (no special chars for compatibility)
openssl rand -base64 24 | tr -d "=+/" | cut -c1-32
```

### Synapse Registration Shared Secret
```bash
# Generate a secure random string
openssl rand -base64 32 | tr -d "=+/"
```

### MAS Secrets
```bash
# Generate a 32-byte (64 hex characters) secret for encryption
openssl rand -hex 32

# Generate a 32-byte (64 hex characters) secret for keys
openssl rand -hex 32
```

### OIDC Client Secrets (if using Authelia)
```bash
# Generate a secure client secret
openssl rand -base64 32 | tr -d "=+/"
```

## Step 3: Configure Environment Variables

Edit `.env` and fill in all the placeholders:

```bash
nano .env
```

Key variables to set:
- `MATRIX_DOMAIN` - Your Matrix server domain (e.g., `matrix.example.com`)
- `ELEMENT_DOMAIN` - Your Element web client domain (e.g., `element.example.com`)
- `POSTGRES_PASSWORD` - Database password from Step 2
- `SYNAPSE_REGISTRATION_SHARED_SECRET` - From Step 2
- `MAS_SECRETS_ENCRYPTION` - 64 hex characters from Step 2
- `MAS_SECRETS_KEYS` - 64 hex characters from Step 2
- `AUTHELIA_CLIENT_SECRET` - If using Authelia, from Step 2

## Step 4: Configure Synapse

```bash
mkdir -p synapse/config
cp templates/homeserver.yaml synapse/config/homeserver.yaml
nano synapse/config/homeserver.yaml
```

Replace all placeholders:
- `{{MATRIX_DOMAIN}}` → Your domain (e.g., `matrix.example.com`)
- `{{POSTGRES_PASSWORD}}` → Your database password
- `{{SYNAPSE_REGISTRATION_SHARED_SECRET}}` → Your registration secret

**IMPORTANT**: The database password in `homeserver.yaml` must match the one in `.env`. If you change the password in `.env`, you MUST update it in `homeserver.yaml` as well.

## Step 5: Configure MAS (Matrix Authentication Service)

```bash
mkdir -p mas/config
cp templates/mas-config.yaml mas/config/config.yaml
nano mas/config/config.yaml
```

Replace all placeholders:
- `{{MATRIX_DOMAIN}}` → Your domain
- `{{POSTGRES_PASSWORD}}` → Your database password
- `{{MAS_SECRETS_ENCRYPTION}}` → 64 hex characters
- `{{MAS_SECRETS_KEYS}}` → 64 hex characters
- `{{AUTHELIA_URL}}` → If using Authelia, your Authelia URL (e.g., `https://auth.example.com`)
- `{{AUTHELIA_CLIENT_ID}}` → If using Authelia, your client ID (e.g., `matrix_mas`)
- `{{AUTHELIA_CLIENT_SECRET}}` → If using Authelia, your client secret

**If NOT using Authelia**: Comment out or remove the entire `upstream_oauth2` section in `mas-config.yaml`.

## Step 6: Configure Element Web

```bash
mkdir -p element/config
cp templates/element-config.json element/config/config.json
nano element/config/config.json
```

Replace:
- `{{MATRIX_DOMAIN}}` → Your domain
- `{{ELEMENT_DOMAIN}}` → Your Element domain

## Step 7: Setup Caddy Reverse Proxy

If Caddy is on the **same server**:

```bash
mkdir -p caddy
cp templates/Caddyfile caddy/Caddyfile
nano caddy/Caddyfile
```

If Caddy is on a **separate server**:

1. Copy `templates/Caddyfile` to your Caddy server
2. Modify the `reverse_proxy` directives to point to your Matrix server IP:
   ```
   reverse_proxy http://YOUR_MATRIX_SERVER_IP:8008
   ```
3. Ensure ports 8008, 8080, 8081 are accessible from your Caddy server (firewall rules)

Replace all placeholders:
- `{{MATRIX_DOMAIN}}` → Your domain
- `{{ELEMENT_DOMAIN}}` → Your Element domain

## Step 8: Configure Authelia (Optional)

If you're using Authelia as an upstream OIDC provider, add this client configuration to your Authelia server:

```bash
nano /etc/authelia/configuration.yml
```

Add the OIDC client snippet from `templates/authelia-client.yml` to your `identity_providers.oidc.clients` section.

**Important**:
- Replace all placeholders in the template
- The `client_id` must match what you configured in MAS
- The `client_secret` must be hashed using `authelia crypto hash generate pbkdf2`
- The redirect URI must match: `https://{{MATRIX_DOMAIN}}/oauth2/callback`

## Step 9: Start the Stack

```bash
# Create necessary directories and set permissions
mkdir -p synapse/data mas/data element-admin/data postgres/data

# Start PostgreSQL first to allow it to initialize
docker compose up -d postgres

# Wait for PostgreSQL to be ready (about 10-15 seconds)
sleep 15

# Check if database is ready
docker compose exec postgres pg_isready -U synapse

# Start all services
docker compose up -d

# Check logs for any errors
docker compose logs -f
```

## Step 10: Verify Services

Check that all services are running:

```bash
docker compose ps
```

All services should be in "Up" state.

Test endpoints:
```bash
# Test Synapse
curl https://matrix.example.com/_matrix/client/versions

# Test Element
curl https://element.example.com/

# Test MAS health endpoint
curl http://localhost:8080/health
```

## Step 11: Create Your First Admin User

```bash
# Generate admin user via MAS
docker compose exec mas mas-cli manage register-user \
  --username admin \
  --admin
```

Follow the prompts to set a password. This creates a native MAS user with admin privileges.

## Step 12: Access Element Web

1. Open your browser and navigate to `https://element.example.com`
2. Click "Sign In"
3. You'll be redirected to MAS login
4. If using Authelia, click "Sign in with Authelia" (or your configured provider name)
5. Complete authentication
6. You should now be logged into Element!

## Step 13: Access Element Admin

Navigate to `http://YOUR_SERVER_IP:8081` (or configure Caddy to expose it on a subdomain)

Login with your admin credentials created in Step 11.

## Troubleshooting

### Database Connection Errors

**Symptom**: Services fail to connect to database

**Solution**:
1. Ensure PostgreSQL is fully started: `docker compose logs postgres`
2. Verify password matches in `.env`, `homeserver.yaml`, and `mas-config.yaml`
3. Restart services: `docker compose restart synapse mas`

### MAS Configuration Errors

**Symptom**: MAS fails to start with "invalid secret length" error

**Solution**:
- Verify `MAS_SECRETS_ENCRYPTION` and `MAS_SECRETS_KEYS` are exactly 64 hex characters
- Generate new secrets: `openssl rand -hex 32`

### Cannot Create Users

**Symptom**: User registration fails

**Solution**:
1. Check MAS logs: `docker compose logs mas`
2. Ensure MAS can connect to Synapse: `docker compose exec mas curl http://synapse:8008/_matrix/client/versions`
3. Verify database migrations ran: `docker compose logs mas | grep migration`

### OIDC Login Fails

**Symptom**: Redirect to Authelia works, but login fails to complete

**Solution**:
1. Verify redirect URI in Authelia matches exactly: `https://matrix.example.com/oauth2/callback`
2. Check client_id and client_secret match between MAS and Authelia
3. Review Authelia logs for errors
4. Ensure Authelia is accessible from the Matrix server (network/firewall)

### Port Conflicts

**Symptom**: Docker fails to bind ports

**Solution**:
1. Check what's using the ports: `sudo netstat -tlnp | grep -E '8008|8080|8081|5432'`
2. Either stop the conflicting service or modify ports in `docker-compose.yml`

### Element Web Shows "Cannot Connect to Homeserver"

**Symptom**: Element loads but cannot connect

**Solution**:
1. Verify Caddy is proxying correctly: `curl -v https://matrix.example.com/_matrix/client/versions`
2. Check Element config.json has correct homeserver URL
3. Verify CORS headers are set in Caddy
4. Check browser console for specific errors

## Maintenance

### Backing Up

```bash
# Backup database
docker compose exec postgres pg_dump -U synapse synapse > backup-$(date +%Y%m%d).sql

# Backup Synapse data
tar -czf synapse-data-$(date +%Y%m%d).tar.gz synapse/data/

# Backup MAS data
tar -czf mas-data-$(date +%Y%m%d).tar.gz mas/data/
```

### Updating

```bash
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Check logs
docker compose logs -f
```

### Changing Database Password

**CRITICAL**: If you need to change the database password:

1. Stop all services: `docker compose down`
2. Update password in `.env`
3. Update password in `synapse/config/homeserver.yaml`
4. Update password in `mas/config/config.yaml`
5. Start PostgreSQL: `docker compose up -d postgres`
6. Change password in PostgreSQL:
   ```bash
   docker compose exec postgres psql -U synapse -c "ALTER USER synapse PASSWORD 'NEW_PASSWORD';"
   ```
7. Start all services: `docker compose up -d`

## Security Considerations

1. **Secrets**: Never commit `.env` or config files with real secrets to version control
2. **Firewall**: Only expose ports 80 and 443 (via Caddy) to the internet
3. **Updates**: Regularly update Docker images for security patches
4. **Backups**: Implement automated backups of database and data directories
5. **Monitoring**: Set up monitoring and alerting for service health
6. **Rate Limiting**: Caddy includes basic rate limiting; consider additional protection
7. **SSL/TLS**: Let Caddy handle certificates automatically; ensure they're valid

## Advanced Configuration

### Adding Federation

To federate with other Matrix servers, ensure:
1. DNS SRV records are set: `_matrix._tcp.example.com` → `matrix.example.com:443`
2. Caddy is configured to proxy federation traffic (included in template)
3. Firewall allows incoming HTTPS traffic

### Enabling Registration

By default, registration is disabled. To enable via MAS:

Edit `mas/config/config.yaml` and adjust the `matrix.registration` section.

### Custom Themes

Place custom Element themes in `element/config/themes/` and reference them in `element-config.json`.

## Support

For issues specific to:
- **Synapse**: https://github.com/element-hq/synapse
- **MAS**: https://github.com/element-hq/matrix-authentication-service
- **Element**: https://github.com/element-hq/element-web
- **This setup**: Open an issue in this repository

## License

This setup guide and templates are provided as-is for self-hosting Matrix servers.
