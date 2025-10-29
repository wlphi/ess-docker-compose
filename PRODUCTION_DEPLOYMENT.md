# Production Deployment Guide

This guide covers deploying the Matrix stack to production with all critical fixes applied.

## Overview

Two production architectures are supported:

1. **Single-Machine Deployment** (Recommended for most users)
   - All services on one server
   - Caddy handles SSL termination with Let's Encrypt
   - Simpler setup and maintenance

2. **Multi-Machine Deployment** (Advanced)
   - Caddy on separate SSL termination server
   - Matrix services on application server
   - Better for high-traffic scenarios

## Critical Fixes Applied

All production deployments include fixes for:

- **Issue #9**: PostgreSQL data persistence across deployments
- **Issue #10**: DNS resolution and certificate trust (not needed in production with real DNS/certs)
- **Authelia Optional**: Can deploy with or without Authelia SSO
- **Bridge Support**: Automatic bridge directory mounting in Synapse
- **MAS Healthcheck**: Disabled for distroless image compatibility

## Single-Machine Production Deployment

### Prerequisites

- Ubuntu/Debian Linux server with public IP
- Domain name with DNS configured
- Ports 80, 443 open in firewall
- Docker and Docker Compose installed

### DNS Configuration

Configure A/AAAA records for your domain:

```
matrix.yourdomain.com    → Your server IP
element.yourdomain.com   → Your server IP
auth.yourdomain.com      → Your server IP
authelia.yourdomain.com  → Your server IP (if using Authelia)
```

###Step-by-Step Deployment

#### 1. Clone and Configure

```bash
cd /opt
git clone <your-repo> matrix-stack
cd matrix-stack
```

#### 2. Run Deployment Script

```bash
sudo ./deploy.sh
```

Choose:
- Deployment type: **Production**
- Include Authelia: **Yes** or **No** (your choice)

Provide:
- Your domain (e.g., `yourdomain.com`)
- Email for Let's Encrypt notifications

#### 3. Review Generated Configs

The script creates:
- `.env` with all secrets
- `docker-compose.production.yml` (already updated with fixes)
- `caddy/Caddyfile.production` for single-machine setup
- All service configurations

#### 4. Start Services

**Without Authelia:**
```bash
sudo docker compose -f docker-compose.production.yml up -d
```

**With Authelia:**
```bash
sudo docker compose -f docker-compose.production.yml --profile authelia up -d
```

#### 5. Verify Services

```bash
# Check all services running
sudo docker compose -f docker-compose.production.yml ps

# Check logs
sudo docker compose -f docker-compose.production.yml logs

# Test endpoints
curl https://matrix.yourdomain.com/_matrix/client/versions
curl https://auth.yourdomain.com/.well-known/openid-configuration
```

#### 6. Configure Bridges (Optional)

```bash
sudo ./setup-bridges.sh
```

This automatically configures Telegram, WhatsApp, and Signal bridges. Users will need to link their accounts by messaging the bridge bots in Element.

### Certificate Management

Caddy automatically:
- Obtains Let's Encrypt certificates
- Renews certificates before expiry
- Handles HTTPS redirects

Certificates are stored in `caddy/data/` and persist across restarts.

### Firewall Configuration

Required ports:
```bash
# HTTP (Let's Encrypt validation)
sudo ufw allow 80/tcp

# HTTPS
sudo ufw allow 443/tcp

# Federation (if using Matrix federation)
sudo ufw allow 8448/tcp
```

## Multi-Machine Production Deployment

### Architecture

```
Internet
   ↓
Caddy Server (SSL termination)
   ↓
Matrix Server (Synapse, MAS, Element, Bridges)
   ↓
PostgreSQL
```

### Caddy Server Setup

1. Install Caddy on SSL termination server
2. Copy generated `caddy/Caddyfile.production` to Caddy server
3. Update IP addresses in Caddyfile to point to Matrix server
4. Start Caddy

### Matrix Server Setup

1. Run deployment script, choose production mode
2. Use `docker-compose.production.yml` but remove Caddy service
3. Expose ports 8008, 8080, 8090 to Caddy server only (firewall)
4. Start services

## Data Persistence and Backups

### Important Directories

```
postgres/data/     # PostgreSQL database (CRITICAL)
synapse/data/      # Synapse state and media
mas/data/          # MAS sessions and state
bridges/*/config/  # Bridge configurations and sessions
caddy/data/        # SSL certificates
```

### Backup Strategy

**Daily backups:**
```bash
#!/bin/bash
# backup-matrix.sh
BACKUP_DIR="/backup/matrix-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Stop services
cd /opt/matrix-stack
docker compose -f docker-compose.production.yml stop

# Backup data directories
tar -czf "$BACKUP_DIR/postgres.tar.gz" postgres/data/
tar -czf "$BACKUP_DIR/synapse.tar.gz" synapse/data/
tar -czf "$BACKUP_DIR/mas.tar.gz" mas/data/
tar -czf "$BACKUP_DIR/bridges.tar.gz" bridges/
cp .env "$BACKUP_DIR/"

# Restart services
docker compose -f docker-compose.production.yml up -d
```

**PostgreSQL dumps:**
```bash
# Dump database (can be done while running)
docker exec matrix-postgres pg_dumpall -U synapse > backup-$(date +%Y%m%d).sql
```

## Monitoring and Maintenance

### Health Checks

```bash
# Check service status
docker compose -f docker-compose.production.yml ps

# Check resource usage
docker stats

# Check logs for errors
docker compose -f docker-compose.production.yml logs --tail=100 | grep -i error
```

### Log Rotation

Configure Docker log rotation in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### Certificate Renewal

Caddy handles automatic renewal. Monitor logs:

```bash
docker compose -f docker-compose.production.yml logs caddy | grep -i "renew\|cert"
```

## Troubleshooting

### Issue: Services Won't Start After Update

**Cause**: PostgreSQL data directory password mismatch (Issue #9)

**Solution**:
```bash
# Deploy script now detects this automatically
# If you encounter it manually:
docker compose stop
sudo rm -rf postgres/data/
# Re-run deploy.sh or manually recreate with correct password
```

### Issue: Element Can't Connect to Homeserver

**Cause**: CORS or MAS delegation not configured

**Solution**:
```bash
# Check Synapse delegates to MAS
curl https://matrix.yourdomain.com/.well-known/matrix/client

# Should return:
# {"m.homeserver":{"base_url":"https://matrix.yourdomain.com"},
#  "m.authentication":{"issuer":"https://auth.yourdomain.com/"}}
```

### Issue: Bridges Keep Restarting

**Cause**: Configuration not complete or registration not loaded

**Solution**:
```bash
# Run bridge setup script
sudo ./setup-bridges.sh

# Check bridge logs
docker compose -f docker-compose.production.yml logs mautrix-whatsapp

# Ensure Synapse has bridge registrations mounted
grep "app_service_config_files" synapse/data/homeserver.yaml
```

### Issue: Let's Encrypt Certificate Fails

**Causes**:
- DNS not propagated yet
- Port 80 blocked
- Rate limit hit

**Solutions**:
```bash
# Check DNS
dig matrix.yourdomain.com

# Check port 80 accessible
curl http://matrix.yourdomain.com

# Check Caddy logs
docker compose logs caddy

# If rate limited, use staging:
# Edit Caddyfile, add to global options:
# acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
```

## Security Hardening

### 1. Enable Authelia 2FA

If using Authelia, enable two-factor authentication in `authelia/config/configuration.yml`:

```yaml
default_2fa_method: "totp"

access_control:
  default_policy: two_factor  # Require 2FA for everything
```

### 2. Restrict Admin API

Caddy admin API should not be publicly accessible:

```bash
# Use firewall to restrict to localhost only
sudo ufw deny 2019/tcp
```

Or in Caddyfile:
```
admin localhost:2019
```

### 3. Regular Updates

```bash
# Update Docker images
cd /opt/matrix-stack
docker compose -f docker-compose.production.yml pull
docker compose -f docker-compose.production.yml up -d
```

### 4. Review Permissions

```yaml
# In MAS config (mas/config/config.yaml)
policy:
  registration:
    enabled: false  # Disable open registration in production
    require_email: true
```

### 5. PostgreSQL Security

```bash
# Restrict PostgreSQL to internal network only
# Already configured - exposed only to Docker network
```

## Upgrading

### Minor Updates (Docker Images)

```bash
cd /opt/matrix-stack
docker compose -f docker-compose.production.yml pull
docker compose -f docker-compose.production.yml up -d
```

### Major Updates (Configuration Changes)

1. Backup everything first
2. Pull latest deployment scripts
3. Review BUGFIXES.md for any new issues
4. Test in local deployment first
5. Apply to production during maintenance window

## Performance Tuning

### PostgreSQL

Edit `postgres/init/postgres-config.sql`:

```sql
-- For production server with 8GB RAM:
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
ALTER SYSTEM SET work_mem = '32MB';
```

### Synapse

Edit `synapse/data/homeserver.yaml`:

```yaml
# Increase cache sizes for production
caches:
  global_factor: 2.0  # Double default cache sizes

# Enable media retention
media_retention:
  local_media_lifetime: 90d
  remote_media_lifetime: 14d
```

## Federation

To enable federation with other Matrix servers:

1. Ensure port 8448 is open
2. Configure federation in Synapse (`synapse/data/homeserver.yaml`):
   ```yaml
   federation:
     enabled: true
   ```
3. Verify `.well-known/matrix/server` serves correct federation endpoint

Test federation:
```bash
curl https://matrix.yourdomain.com/_matrix/federation/v1/version
```

## Support and Resources

- Matrix Synapse docs: https://element-hq.github.io/synapse/
- MAS docs: https://element-hq.github.io/matrix-authentication-service/
- Authelia docs: https://www.authelia.com/
- Caddy docs: https://caddyserver.com/docs/

- Project BUGFIXES.md: Documents all critical undocumented issues
- QUICK_REFERENCE.md: Common operations and commands
