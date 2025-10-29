# Matrix Stack Quick Reference

Quick command reference for common operations.

## 🚀 Deployment

```bash
# First time deployment
chmod +x deploy.sh
./deploy.sh

# During deployment, you'll be asked:
# - Deployment type (local/production)
# - Whether to include Authelia SSO (Y/n)

# Update /etc/hosts first!
sudo nano /etc/hosts
# Add (for local deployment):
# 127.0.0.1  matrix.example.test
# 127.0.0.1  element.example.test
# 127.0.0.1  auth.example.test
# 127.0.0.1  authelia.example.test  (only if using Authelia)
```

## 🔑 Authentication Options

The deployment script offers two authentication modes:

### With Authelia (Recommended)
- Full SSO with 2FA support
- LDAP/file-based user management
- Centralized authentication
- Includes Redis for session storage

### Without Authelia (MAS Only)
- MAS handles password authentication directly
- Simpler setup for basic use cases
- No upstream OAuth provider required
- No Redis dependency

## 🌐 Access URLs

| Service | URL |
|---------|-----|
| Element Web | https://element.example.test |
| Matrix API | https://matrix.example.test |
| MAS Auth | https://auth.example.test |
| Authelia SSO | https://authelia.example.test |
| Caddy Admin | http://localhost:2019 |

## 📦 Service Management

### With Authelia

```bash
# View all services
docker compose -f docker-compose.local.yml --profile authelia ps

# Start all services
docker compose -f docker-compose.local.yml --profile authelia up -d

# Stop all services
docker compose -f docker-compose.local.yml --profile authelia down

# Restart specific service
docker compose -f docker-compose.local.yml --profile authelia restart mas

# Restart all services
docker compose -f docker-compose.local.yml --profile authelia restart
```

### Without Authelia (MAS Only)

```bash
# View all services
docker compose -f docker-compose.local.yml ps

# Start all services
docker compose -f docker-compose.local.yml up -d

# Stop all services
docker compose -f docker-compose.local.yml down

# Restart specific service
docker compose -f docker-compose.local.yml restart mas

# Restart all services
docker compose -f docker-compose.local.yml restart
```

## 📝 Logs

```bash
# Follow all logs (add --profile authelia if using Authelia)
docker compose -f docker-compose.local.yml logs -f
docker compose -f docker-compose.local.yml --profile authelia logs -f  # with Authelia

# Follow specific service
docker compose -f docker-compose.local.yml logs -f mas
docker compose -f docker-compose.local.yml --profile authelia logs -f authelia  # Authelia logs

# Last 100 lines
docker compose -f docker-compose.local.yml logs --tail=100 synapse

# Search logs for errors
docker compose -f docker-compose.local.yml logs mas | grep ERROR
```

## 🗄️ Database Operations

```bash
# Connect to PostgreSQL
docker compose -f docker-compose.local.yml exec postgres psql -U synapse

# Connect to specific database
docker compose -f docker-compose.local.yml exec postgres psql -U synapse -d mas

# List databases
docker compose -f docker-compose.local.yml exec postgres psql -U synapse -c "\l"

# MAS provider check
docker compose -f docker-compose.local.yml exec postgres psql -U synapse -d mas -c \
  "SELECT upstream_oauth_provider_id, fetch_userinfo, issuer FROM upstream_oauth_providers;"
```

## 🔧 Troubleshooting

### Fix MAS Provider Cache

```bash
# Delete provider to force config re-sync
docker compose -f docker-compose.local.yml exec postgres psql -U synapse -d mas << 'EOF'
DELETE FROM upstream_oauth_authorization_sessions WHERE upstream_oauth_provider_id = (SELECT upstream_oauth_provider_id FROM upstream_oauth_providers LIMIT 1);
DELETE FROM upstream_oauth_links WHERE upstream_oauth_provider_id = (SELECT upstream_oauth_provider_id FROM upstream_oauth_providers LIMIT 1);
DELETE FROM upstream_oauth_providers;
EOF

# Restart MAS
docker compose -f docker-compose.local.yml restart mas
```

### Extract Caddy CA Certificate

```bash
# Create certs directory
mkdir -p mas/certs

# Extract certificate
docker compose -f docker-compose.local.yml exec caddy cat \
  /data/caddy/pki/authorities/local/root.crt > mas/certs/caddy-ca.crt

# Restart MAS
docker compose -f docker-compose.local.yml restart mas
```

### Check Service Health

```bash
# Check all container health
docker compose -f docker-compose.local.yml ps

# Check specific service logs for errors
docker compose -f docker-compose.local.yml logs --tail=50 mas | grep ERROR

# Test HTTPS endpoints
curl -k https://matrix.example.test/_matrix/client/versions
curl -k https://auth.example.test/.well-known/openid-configuration
curl -I -k https://auth.example.test/assets/shared-CVCHz34K.css
```

## 👤 User Management

### Add Authelia User

```bash
# Generate password hash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'userpassword'

# Edit users database
nano authelia/config/users_database.yml

# Add user:
# username:
#   displayname: "Full Name"
#   password: "$argon2id$..."
#   email: user@matrix.example.test
#   groups:
#     - users

# Restart Authelia
docker compose -f docker-compose.local.yml restart authelia
```

### Change Admin Password

```bash
# Generate new password hash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'newpassword'

# Update authelia/config/users_database.yml
# Replace admin password hash

# Restart Authelia
docker compose -f docker-compose.local.yml restart authelia
```

## 💾 Backup & Restore

### Quick Backup

```bash
# Backup databases
docker compose -f docker-compose.local.yml exec -T postgres pg_dumpall -U synapse \
  > backup_$(date +%Y%m%d).sql

# Backup configs
tar -czf config_backup_$(date +%Y%m%d).tar.gz \
  authelia/config mas/config synapse/data/homeserver.yaml \
  authelia_private.pem mas-signing.key .env
```

### Full Backup

```bash
# Create backup directory
mkdir -p backups/$(date +%Y%m%d)

# Backup everything
docker compose -f docker-compose.local.yml exec -T postgres pg_dumpall -U synapse \
  > backups/$(date +%Y%m%d)/databases.sql

tar -czf backups/$(date +%Y%m%d)/configs.tar.gz \
  authelia/config mas/config synapse/data/homeserver.yaml \
  element/config authelia_private.pem mas-signing.key .env

tar -czf backups/$(date +%Y%m%d)/media.tar.gz synapse/data/media_store
```

### Restore from Backup

```bash
# Restore databases
docker compose -f docker-compose.local.yml exec -T postgres psql -U synapse < backup.sql

# Restore configs
tar -xzf configs.tar.gz

# Restart all services
docker compose -f docker-compose.local.yml restart
```

## 🔄 Updates

```bash
# Pull latest images
docker compose -f docker-compose.local.yml pull

# Recreate containers
docker compose -f docker-compose.local.yml up -d

# Remove old images
docker image prune -a
```

## 🧹 Cleanup

```bash
# Stop and remove containers (keeps data)
docker compose -f docker-compose.local.yml down

# Stop and remove everything INCLUDING DATA (⚠️ DESTRUCTIVE!)
docker compose -f docker-compose.local.yml down -v
rm -rf postgres/data synapse/data mas/data

# Remove unused Docker resources
docker system prune -a
```

## 🔍 Verification Tests

```bash
# Test Matrix API
curl -k https://matrix.example.test/_matrix/client/versions | jq

# Test Matrix well-known
curl -k https://matrix.example.test/.well-known/matrix/client | jq

# Test MAS OIDC discovery
curl -k https://auth.example.test/.well-known/openid-configuration | jq

# Test Authelia OIDC discovery
curl -k https://authelia.example.test/.well-known/openid-configuration | jq

# Test MAS assets
curl -I -k https://auth.example.test/assets/shared-CVCHz34K.css

# Check PostgreSQL health
docker compose -f docker-compose.local.yml exec postgres pg_isready -U synapse
```

## 🚨 Emergency Commands

### Services Won't Start

```bash
# Check what's failing
docker compose -f docker-compose.local.yml ps

# View logs
docker compose -f docker-compose.local.yml logs --tail=50

# Force recreate
docker compose -f docker-compose.local.yml up -d --force-recreate

# Nuclear option (stops all, removes containers, restart fresh)
docker compose -f docker-compose.local.yml down
docker compose -f docker-compose.local.yml up -d
```

### Database Issues

```bash
# Stop all services
docker compose -f docker-compose.local.yml down

# Start only PostgreSQL
docker compose -f docker-compose.local.yml up -d postgres

# Wait and check
sleep 10
docker compose -f docker-compose.local.yml logs postgres

# If working, start everything else
docker compose -f docker-compose.local.yml up -d
```

### Port Conflicts

```bash
# Find what's using port 443
sudo lsof -i :443

# Kill process if needed
sudo kill -9 <PID>

# Or change ports in docker-compose.local.yml
nano docker-compose.local.yml
# Change "443:443" to "8443:443"
```

## 📚 Documentation Quick Links

- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Complete deployment guide
- **[BUGFIXES.md](BUGFIXES.md)** - Critical fixes and troubleshooting
- **[README.md](README.md)** - Quick start overview
- **[PRODUCTION.md](PRODUCTION.md)** - Production deployment guide

## 🆘 Common Error Solutions

| Error | Fix |
|-------|-----|
| CSS not loading | Check MAS has `assets` resource, restart MAS |
| Empty string template error | Verify `fetch_userinfo: true`, delete provider from DB |
| Redirect URI mismatch | Add all redirect URIs to Authelia config |
| Cookie domain error | Use `example.test` not `.localhost` |
| SSL certificate error | Extract Caddy CA cert, mount in MAS |
| Database connection failed | Restart postgres first, wait, then start others |

## 📞 Getting Help

1. Check service logs: `docker compose logs -f service-name`
2. Review [BUGFIXES.md](BUGFIXES.md) for detailed solutions
3. Run validation: `./validate-setup.sh`
4. Check database state with queries above
5. Try clean restart: `down` then `up -d`

---

**💡 Tip:** Bookmark this page for quick access to common commands!
