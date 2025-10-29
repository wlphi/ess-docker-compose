# Production Deployment Guide

This guide covers deploying the Matrix stack in a **distributed production environment** as specified in the requirements:
- **Matrix server** (Synapse, MAS, Element, Bridges) on one machine
- **Authelia** (SSO provider) on a separate machine
- **Caddy** (SSL termination/reverse proxy) on a separate machine

## Architecture Overview

```
┌─────────────────────┐
│   Internet          │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────┐
│  Machine 1: Caddy Server    │
│  - SSL termination          │
│  - Reverse proxy            │
│  - Ports: 80, 443, 8448     │
└──────────┬──────────────────┘
           │
    ┌──────┴──────┐
    │             │
    ▼             ▼
┌────────────┐  ┌─────────────────────┐
│ Machine 2: │  │ Machine 3: Matrix   │
│ Authelia   │  │ - Synapse           │
│ - SSO/2FA  │  │ - Element Web       │
│ - OIDC     │  │ - MAS               │
│            │  │ - PostgreSQL        │
│            │  │ - Bridges           │
└────────────┘  └─────────────────────┘
```

## Prerequisites

- 3 machines (physical or virtual)
- Docker and Docker Compose on all machines
- Domain names with DNS configured:
  - `matrix.yourdomain.com` → Caddy server IP
  - `element.yourdomain.com` → Caddy server IP
  - `mas.yourdomain.com` → Caddy server IP
  - `auth.yourdomain.com` → Caddy server IP
- Firewall rules allowing communication between machines

## Machine 1: Caddy Server (SSL Termination)

### Setup

1. Copy the `caddy-server/` directory to the Caddy machine
2. Edit `caddy-server/.env`:
   ```bash
   MATRIX_SERVER_IP=<Machine 3 IP>
   AUTHELIA_SERVER_IP=<Machine 2 IP>
   ```
3. Edit `caddy-server/Caddyfile` and replace `yourdomain.com` with your actual domain
4. Start Caddy:
   ```bash
   cd caddy-server
   docker compose up -d
   ```

### Firewall Configuration

**Allow incoming:**
- Port 80 (HTTP - for ACME challenge)
- Port 443 (HTTPS)
- Port 8448 (Matrix Federation)

**Allow outgoing to:**
- Machine 2 (Authelia): Port 9091
- Machine 3 (Matrix): Ports 8008, 8080, 8081, 8448

### Verify

Check Caddy logs:
```bash
docker compose logs -f caddy
```

Visit `https://auth.yourdomain.com` - you should see SSL working (initially might show connection refused until backends are up).

## Machine 2: Authelia Server (SSO)

### Setup

1. Copy the `authelia-server/` directory to the Authelia machine

2. Edit `authelia-server/.env`:
   ```bash
   POSTGRES_PASSWORD=<secure-password>
   AUTHELIA_JWT_SECRET=<generate-with-openssl-rand-base64-32>
   AUTHELIA_SESSION_SECRET=<generate-with-openssl-rand-base64-32>
   AUTHELIA_STORAGE_ENCRYPTION_KEY=<generate-with-openssl-rand-base64-32>
   ```

3. Generate RSA key for OIDC:
   ```bash
   openssl genrsa -out authelia_private.pem 4096
   ```

4. Edit `authelia-server/config/configuration.yml`:
   - Replace all `yourdomain.com` with your actual domain
   - Paste the RSA key into `issuer_private_key`
   - Configure SMTP settings for email notifications
   - Generate client secret:
     ```bash
     docker run authelia/authelia:latest authelia crypto hash generate pbkdf2 \
       --variant sha512 --random --random.length 72 --random.charset rfc3986
     ```
   - Update `client_secret` with the hash (keep the plain text secret for MAS config)

5. Create user accounts in `authelia-server/config/users_database.yml`:
   ```bash
   # Generate password hash
   docker run authelia/authelia:latest authelia crypto hash generate argon2 \
     --password 'yourpassword'
   ```

6. Start Authelia:
   ```bash
   cd authelia-server
   docker compose up -d
   ```

### Firewall Configuration

**Allow incoming from:**
- Machine 1 (Caddy): Port 9091
- Machine 3 (Matrix): Port 9091 (for MAS OIDC communication)

**Allow outgoing to:**
- SMTP server (for notifications)

### Verify

Check Authelia logs:
```bash
docker compose logs -f authelia
```

Test locally:
```bash
curl http://localhost:9091/api/health
```

## Machine 3: Matrix Server

### Setup

1. Copy the main directory (with docker-compose.production.yml) to the Matrix machine

2. Use the production compose file:
   ```bash
   cp docker-compose.production.yml docker-compose.yml
   # Or use: docker compose -f docker-compose.production.yml
   ```

3. Edit `.env`:
   ```bash
   DOMAIN=yourdomain.com
   SERVER_NAME=yourdomain.com
   POSTGRES_PASSWORD=<secure-password>
   MAS_SECRET_KEY=<generate-with-openssl-rand-base64-32>
   # ... other secrets
   ```

4. Generate Synapse configuration:
   ```bash
   ./setup-synapse.sh
   ```

5. Edit `synapse/data/homeserver.yaml`:

   **Update domain:**
   ```yaml
   server_name: "yourdomain.com"
   public_baseurl: "https://matrix.yourdomain.com"
   ```

   **Configure PostgreSQL:**
   ```yaml
   database:
     name: psycopg2
     args:
       user: synapse
       password: YOUR_POSTGRES_PASSWORD
       database: synapse
       host: postgres
       port: 5432
       cp_min: 5
       cp_max: 10
   ```

   **Add MAS integration:**
   ```yaml
   experimental_features:
     msc3861:
       enabled: true
       issuer: https://mas.yourdomain.com/
       client_id: element-web
       client_auth_method: none
       admin_token: YOUR_ADMIN_TOKEN
   ```

   **Configure trusted key servers:**
   ```yaml
   trusted_key_servers:
     - server_name: "matrix.org"
   ```

6. Update Element config `element/config/config.production.json`:
   - Replace all `yourdomain.com` with your actual domain

7. Update MAS config `mas/config/config.production.yaml`:
   - Replace all `yourdomain.com` with your actual domain
   - Update database password
   - Generate and add RSA signing key:
     ```bash
     openssl genrsa 4096 | openssl pkcs8 -topk8 -nocrypt > mas-signing.key
     cat mas-signing.key
     ```
   - Update `upstream_oauth2.providers[0].issuer` to `https://auth.yourdomain.com`
   - Update `upstream_oauth2.providers[0].client_secret` with the plain text secret from Authelia

8. Start the stack:
   ```bash
   # Start PostgreSQL first
   docker compose up -d postgres

   # Wait 10 seconds, then start everything
   docker compose up -d
   ```

### Firewall Configuration

**Allow incoming from:**
- Machine 1 (Caddy): Ports 8008, 8080, 8081, 8448
- Machine 2 (Authelia): None required (Matrix initiates OIDC to Authelia)

**Allow outgoing to:**
- Machine 2 (Authelia): Port 9091 (for OIDC)
- Internet: Port 8448 (for Matrix federation)

### Verify

Check all services:
```bash
docker compose ps
docker compose logs -f
```

## Element-X Mobile Client Setup

Element-X is the next-generation Matrix client for iOS and Android with native support for MAS/OIDC.

### Download

- **iOS**: [App Store - Element X](https://apps.apple.com/app/element-x/id6451362875)
- **Android**: [Google Play - Element X](https://play.google.com/store/apps/details?id=io.element.android.x)

### Configuration

1. Open Element-X
2. Tap "Sign In"
3. Enter your homeserver: `yourdomain.com` or `https://matrix.yourdomain.com`
4. Element-X will auto-discover your MAS configuration via `.well-known`
5. You'll be redirected to MAS, then to Authelia
6. Log in with your Authelia credentials
7. Complete 2FA if required
8. Grant permissions and you're in!

### Troubleshooting Element-X

If auto-discovery fails:
1. Check `.well-known/matrix/client` is accessible at `https://yourdomain.com/.well-known/matrix/client`
2. Verify Caddy is serving the well-known endpoints correctly
3. Try using the full homeserver URL: `https://matrix.yourdomain.com`

## Bridge Setup (Optional)

Bridges work the same in production. After the main stack is running:

1. Run bridge setup:
   ```bash
   ./setup-bridges.sh
   ```

2. Configure each bridge with your production domain:
   - homeserver: `http://synapse:8008`
   - domain: `yourdomain.com`

3. Register bridges with Synapse (see SETUP.md)

4. Restart Synapse:
   ```bash
   docker compose restart synapse
   ```

## Network Communication Matrix

| From | To | Port | Protocol | Purpose |
|------|-----|------|----------|---------|
| Internet | Caddy | 80, 443 | HTTPS | Public access |
| Internet | Caddy | 8448 | HTTPS | Federation |
| Caddy | Authelia | 9091 | HTTP | SSO proxy |
| Caddy | Matrix | 8008 | HTTP | Synapse API proxy |
| Caddy | Matrix | 8080 | HTTP | Element proxy |
| Caddy | Matrix | 8081 | HTTP | MAS proxy |
| Matrix (MAS) | Authelia | 9091 | HTTP | OIDC provider |
| Matrix (Synapse) | Internet | 8448 | HTTPS | Federation |

## SSL/TLS Certificates

Caddy automatically obtains and renews Let's Encrypt certificates for all configured domains.

**Requirements:**
- Domains must point to Caddy server IP
- Port 80 must be accessible for ACME challenge
- Email notifications: Caddy will use `admin@yourdomain.com` by default

**Check certificates:**
```bash
# On Caddy machine
docker compose exec caddy caddy list-certificates
```

## Testing the Production Setup

### 1. Test Authelia
```bash
curl https://auth.yourdomain.com/api/health
# Should return: {"status":"UP"}
```

### 2. Test Matrix Synapse
```bash
curl https://matrix.yourdomain.com/_matrix/client/versions
# Should return JSON with supported Matrix versions
```

### 3. Test MAS
```bash
curl https://mas.yourdomain.com/health
# Should return health status
```

### 4. Test Well-Known
```bash
curl https://yourdomain.com/.well-known/matrix/client
# Should return homeserver discovery JSON
```

### 5. Test Element Web
Visit `https://element.yourdomain.com` and try to sign in.

### 6. Test Federation
```bash
# From another server, check federation
curl https://matrix.yourdomain.com:8448/_matrix/federation/v1/version
```

## Monitoring and Maintenance

### Logs

**Caddy:**
```bash
cd caddy-server && docker compose logs -f caddy
```

**Authelia:**
```bash
cd authelia-server && docker compose logs -f authelia
```

**Matrix:**
```bash
docker compose logs -f synapse
docker compose logs -f mas
```

### Updates

**Update all services:**
```bash
# On each machine
docker compose pull
docker compose up -d
```

### Backups

**Machine 2 (Authelia):**
```bash
# Backup Authelia database and config
docker compose exec postgres pg_dump -U authelia authelia > authelia-backup-$(date +%Y%m%d).sql
tar -czf authelia-config-backup-$(date +%Y%m%d).tar.gz config/
```

**Machine 3 (Matrix):**
```bash
# Backup all Matrix data
docker compose exec postgres pg_dumpall -U synapse > matrix-backup-$(date +%Y%m%d).sql
tar -czf matrix-data-backup-$(date +%Y%m%d).tar.gz synapse/data/ mas/data/ bridges/*/config/
```

## Security Checklist

- [ ] All default passwords changed in `.env` files
- [ ] Strong passwords for Authelia users
- [ ] SSH key authentication (disable password auth)
- [ ] Firewall rules configured on all machines
- [ ] Fail2ban or similar intrusion prevention
- [ ] Regular backups scheduled
- [ ] SSL/TLS certificates valid and auto-renewing
- [ ] Monitoring and alerting set up
- [ ] Log rotation configured
- [ ] Review Authelia access control rules
- [ ] Test disaster recovery procedure

## Troubleshooting

### Can't access Element Web

1. Check Caddy logs for proxy errors
2. Verify Matrix machine is accessible from Caddy: `curl http://<matrix-ip>:8080`
3. Check Element container: `docker compose logs element`

### SSO login fails

1. Check MAS can reach Authelia: `docker compose exec mas curl http://<authelia-ip>:9091/api/health`
2. Verify OIDC client secret matches in both configs
3. Check Authelia logs for authentication errors
4. Verify redirect URIs are correct in Authelia config

### Federation not working

1. Check port 8448 is open on firewall
2. Verify Caddy is proxying federation port
3. Test federation: `https://federationtester.matrix.org/`
4. Check Synapse federation settings

### Certificate issues

1. Verify DNS points to Caddy server
2. Check port 80 is accessible (ACME challenge)
3. View Caddy logs during certificate request
4. Manual cert check: `docker compose exec caddy caddy list-certificates`

## Migration from Local to Production

If you started with local testing and want to migrate:

1. **Backup local data:**
   ```bash
   docker compose exec postgres pg_dumpall -U synapse > local-backup.sql
   tar -czf local-data.tar.gz synapse/data/
   ```

2. **Update all configs** with production domains

3. **Transfer data** to production machines

4. **Restore database** on production:
   ```bash
   cat local-backup.sql | docker compose exec -T postgres psql -U synapse
   ```

5. **Update homeserver.yaml** with new domain

6. **Clear browser cache** and cookies

7. **Test thoroughly** before going live

## Performance Tuning

### PostgreSQL

Edit `postgres/postgresql.conf`:
```ini
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
max_connections = 100
```

### Synapse

Edit `synapse/data/homeserver.yaml`:
```yaml
# Increase worker processes
worker_replication_http_port: 9093

# Enable caching
caches:
  global_factor: 2.0

# Media retention
media_retention:
  local_media_lifetime: 90d
  remote_media_lifetime: 14d
```

### Caddy

For high traffic, consider:
- Multiple Caddy instances behind a load balancer
- CDN for static assets
- Dedicated machine for federation traffic

## Cost Estimates

Typical small deployment (100-500 users):
- **Caddy machine**: 1 CPU, 1GB RAM, 20GB disk (~$5-10/month)
- **Authelia machine**: 1 CPU, 2GB RAM, 20GB disk (~$10-15/month)
- **Matrix machine**: 2-4 CPU, 4-8GB RAM, 100GB disk (~$20-40/month)

Plus domain registration and bandwidth costs.

## Support Resources

- [Matrix Homeserver Admin Guide](https://matrix-org.github.io/synapse/latest/usage/administration/)
- [Authelia Documentation](https://www.authelia.com/integration/openid-connect/introduction/)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [Element-X Documentation](https://element.io/element-x)

## Next Steps

1. Set up monitoring (Prometheus + Grafana)
2. Configure log aggregation (ELK stack or Loki)
3. Implement automated backups
4. Set up alerting (email, Slack, etc.)
5. Document your specific configuration
6. Create runbooks for common operations
7. Plan for scaling (multiple Synapse workers)
