# Complete Matrix Stack Deployment Guide

This guide provides step-by-step instructions for deploying a fully functional, secure Matrix communication stack with SSO authentication.

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Deployment Modes](#deployment-modes)
4. [Local Testing Deployment](#local-testing-deployment)
5. [Production Deployment](#production-deployment)
6. [Post-Deployment Verification](#post-deployment-verification)
7. [Common Issues & Solutions](#common-issues--solutions)
8. [Maintenance](#maintenance)

---

## Overview

This deployment provides a complete Matrix communication stack with:

- **Matrix Synapse** - Homeserver for federation
- **Element Web** - Modern web client
- **Matrix Authentication Service (MAS)** - OIDC-based authentication
- **Authelia** - SSO provider with 2FA support
- **Caddy** - Automatic HTTPS with self-signed certs (local) or Let's Encrypt (production)
- **PostgreSQL** - Shared database for all services
- **Redis** - Session storage for Authelia
- **Bridges** - Telegram, WhatsApp, and Signal integration (optional)

**Key Features:**
- ✅ Full SSO authentication flow with 2FA
- ✅ Automatic HTTPS configuration
- ✅ All critical bugfixes pre-applied
- ✅ Single-command deployment
- ✅ Production-ready architecture

---

## Prerequisites

### System Requirements

**Minimum (Local Testing):**
- 4GB RAM
- 2 CPU cores
- 20GB disk space
- Docker 20.10+ with Docker Compose
- Linux, macOS, or WSL2

**Recommended (Production):**
- 8GB+ RAM
- 4+ CPU cores
- 50GB+ SSD storage
- 3 separate machines (Caddy, Authelia, Matrix)

### Software Requirements

```bash
# Check Docker
docker --version
# Should be 20.10.0 or higher

# Check Docker Compose
docker compose version
# Should be v2.0.0 or higher

# Check OpenSSL (for key generation)
openssl version
```

### Network Requirements

**Local Testing:**
- Ability to edit `/etc/hosts`
- Ports 80, 443, 2019 available

**Production:**
- Valid domain name with DNS access
- SSL/TLS certificates (Let's Encrypt recommended)
- Firewall configuration capability

---

## Deployment Modes

### Mode 1: Local Testing (All-in-One)

**Use Case:** Development, testing, proof-of-concept

**Architecture:**
```
Single Machine
├── Caddy (HTTPS termination)
├── Authelia (SSO)
├── MAS (OIDC)
├── Synapse (Matrix homeserver)
├── Element (Web client)
├── PostgreSQL (Database)
└── Redis (Sessions)
```

**Domains:** `*.example.test` (requires `/etc/hosts` entries)

**Security:** Self-signed certificates (browser warnings expected)

**Deployment Time:** ~10 minutes

---

### Mode 2: Production (Distributed)

**Use Case:** Production deployments, high availability

**Architecture:**
```
Machine 1 (Public-facing)
└── Caddy (SSL termination, Let's Encrypt)

Machine 2 (Internal)
└── Authelia (SSO + PostgreSQL + Redis)

Machine 3 (Internal)
├── Synapse (Matrix homeserver)
├── MAS (OIDC)
├── Element (Web client)
├── Bridges (optional)
└── PostgreSQL (dedicated)
```

**Domains:** Real domains with DNS (e.g., `matrix.example.com`)

**Security:** Let's Encrypt certificates, firewall restrictions

**Deployment Time:** ~30 minutes

---

## Local Testing Deployment

### Step 1: Update /etc/hosts

```bash
sudo nano /etc/hosts
```

Add these lines:
```
127.0.0.1  matrix.example.test
127.0.0.1  element.example.test
127.0.0.1  auth.example.test
127.0.0.1  authelia.example.test
```

**Important:** We use `example.test` (not `.localhost`) because `.localhost` is on the [Public Suffix List](https://publicsuffix.org/) and Authelia rejects it for cookie domains. See [BUGFIXES.md](BUGFIXES.md#1-cookie-domain-on-public-suffix-list) for details.

### Step 2: Clone/Extract the Repository

```bash
cd ~/Documents  # or your preferred location
# If you have the repo, cd into it
cd matrix-2
```

### Step 3: Run the Deployment Script

```bash
chmod +x deploy.sh
./deploy.sh
```

The script will:
1. ✅ Ask for deployment mode (select **1** for local)
2. ✅ Generate all secure secrets automatically
3. ✅ Create RSA keys for Authelia and MAS
4. ✅ Generate a random admin password
5. ✅ Configure all services
6. ✅ Start the Docker stack
7. ✅ Extract Caddy CA certificate for MAS
8. ✅ Display access URLs and credentials

**Expected Output:**
```
╔════════════════════════════════════════════════════════════╗
║       Matrix Stack Automated Deployment Script            ║
║                  Interactive Setup                         ║
╚════════════════════════════════════════════════════════════╝

Select Deployment Type:
  1) Local Testing (All-in-One)
  2) Production (Distributed)

Enter choice [1 or 2]: 1
✓ Selected: Local Testing Mode

[... deployment progress ...]

═══════════════════════════════════════════════════════════
Deployment Complete!
═══════════════════════════════════════════════════════════

Access Points (HTTPS with self-signed certificates):
  • Element Web:  https://element.example.test
  • Matrix API:   https://matrix.example.test
  • MAS (Auth):   https://auth.example.test
  • Authelia:     https://authelia.example.test

Authelia Login Credentials:
  • Username:     admin
  • Password:     [generated-password-here]
  ⚠ SAVE THIS PASSWORD - you'll need it to log in!
```

**⚠️ CRITICAL:** Save the admin password displayed! You'll need it to log in.

### Step 4: Verify Services

```bash
# Check all containers are running
docker compose -f docker-compose.local.yml ps

# Expected output:
# All services should show "Up" or "Up (healthy)"
```

### Step 5: Access Element Web

1. Open browser: **https://element.example.test**
2. Accept the self-signed certificate warning:
   - Click "Advanced"
   - Click "Proceed to element.example.test"
3. Click **"Sign In"**
4. You'll be redirected through:
   - MAS (auth.example.test) →
   - Authelia (authelia.example.test)
5. Log in with:
   - Username: `admin`
   - Password: (from deployment script output)
6. Complete 2FA setup if required (use Google Authenticator or similar)
7. Confirm account linking
8. You should be redirected back to Element, logged in!

### Step 6: Create Your First Room

1. In Element, click the **"+" next to "Rooms"**
2. Click **"Create new room"**
3. Configure:
   - Room name: "General"
   - Make it public or private
   - Enable encryption (recommended)
4. Click **"Create"**
5. Start chatting!

---

## Production Deployment

For production deployment with Let's Encrypt certificates and distributed architecture, see [PRODUCTION.md](PRODUCTION.md).

**Key Differences:**
- Real domains with DNS configuration
- Let's Encrypt for SSL certificates
- Services split across 3 machines for security
- Firewall rules to restrict access
- 2FA mandatory (not optional)
- Backup strategy required

---

## Post-Deployment Verification

### Automated Tests

Run the validation script:

```bash
./validate-setup.sh
```

This checks:
- ✅ All services running
- ✅ Database connectivity
- ✅ OIDC discovery endpoints
- ✅ SSL certificates
- ✅ DNS resolution (local testing)

### Manual Verification

#### 1. Check Service Health

```bash
docker compose -f docker-compose.local.yml ps
```

All services should show status `Up (healthy)` or `Up`.

#### 2. Test HTTPS Endpoints

```bash
# Matrix homeserver
curl -k https://matrix.example.test/_matrix/client/versions

# MAS OIDC discovery
curl -k https://auth.example.test/.well-known/openid-configuration | jq

# Authelia OIDC discovery
curl -k https://authelia.example.test/.well-known/openid-configuration | jq

# Element Web
curl -k https://element.example.test
```

All should return valid responses (not 404 or 500 errors).

#### 3. Test Matrix Well-Known

```bash
curl -k https://matrix.example.test/.well-known/matrix/client | jq
```

Should return:
```json
{
  "m.homeserver": {
    "base_url": "https://matrix.example.test"
  },
  "m.authentication": {
    "issuer": "https://auth.example.test/"
  }
}
```

#### 4. Test MAS Assets (CSS)

```bash
curl -I -k https://auth.example.test/assets/shared-CVCHz34K.css
```

Should return `HTTP/2 200` (not 404).

#### 5. Test Authentication Flow

Follow "Step 5: Access Element Web" above and complete the full SSO flow.

#### 6. Test Database Connectivity

```bash
# Connect to MAS database
docker compose -f docker-compose.local.yml exec postgres psql -U synapse -d mas

# Check provider configuration
SELECT upstream_oauth_provider_id, fetch_userinfo, issuer FROM upstream_oauth_providers;

# Should show:
# - fetch_userinfo: t (true)
# - issuer: https://authelia.example.test

# Exit
\q
```

---

## Common Issues & Solutions

See [BUGFIXES.md](BUGFIXES.md) for comprehensive troubleshooting. Here are the most common issues:

### 1. CSS Not Loading on MAS Pages

**Symptom:** MAS pages load but have no styling (plain HTML)

**Cause:** Missing `assets` resource in MAS configuration

**Solution:**
```bash
# Check MAS config
grep -A 10 "resources:" mas/config/config.yaml

# Should include:
#   - name: assets

# If missing, add it and restart:
docker compose -f docker-compose.local.yml restart mas
```

See: [BUGFIXES.md#2-mas-missing-assets-resource](BUGFIXES.md#2-mas-missing-assets-resource)

---

### 2. Login Fails with "Template rendered to empty string"

**Symptom:** Error in MAS logs: `Template "{{ user.preferred_username }}" rendered to an empty string`

**Cause:** MAS not fetching userinfo from Authelia (fetch_userinfo: false)

**Solution:**
```bash
# Check database
docker compose exec postgres psql -U synapse -d mas -c \
  "SELECT fetch_userinfo FROM upstream_oauth_providers;"

# If shows 'f' (false), update config:
# Edit mas/config/config.yaml and add under provider:
#   fetch_userinfo: true

# Delete provider from database to force re-sync:
docker compose exec postgres psql -U synapse -d mas
DELETE FROM upstream_oauth_authorization_sessions WHERE upstream_oauth_provider_id = (SELECT upstream_oauth_provider_id FROM upstream_oauth_providers LIMIT 1);
DELETE FROM upstream_oauth_links WHERE upstream_oauth_provider_id = (SELECT upstream_oauth_provider_id FROM upstream_oauth_providers LIMIT 1);
DELETE FROM upstream_oauth_providers;
\q

# Restart MAS
docker compose -f docker-compose.local.yml restart mas
```

See: [BUGFIXES.md#3-mas-not-fetching-userinfo](BUGFIXES.md#3-mas-not-fetching-userinfo)

---

### 3. Redirect URI Mismatch Error

**Symptom:** Authelia shows "invalid_request: redirect_uri does not match"

**Cause:** Missing upstream callback URI in Authelia client configuration

**Solution:**
```bash
# Edit authelia/config/configuration.yml
# Under clients -> mas-client -> redirect_uris, ensure you have:
#   - 'https://auth.example.test/callback'
#   - 'https://auth.example.test/oauth2/callback'
#   - 'https://auth.example.test/upstream/callback/01HQW90Z35CMXFJWQPHC3BGZGQ'

# Restart Authelia
docker compose -f docker-compose.local.yml restart authelia
```

See: [BUGFIXES.md#5-authelia-redirect-uri-configuration](BUGFIXES.md#5-authelia-redirect-uri-configuration)

---

### 4. Authelia Cookie Domain Error

**Symptom:** Authelia fails to start with "domain is part of the special public suffix list"

**Cause:** Using `.localhost`, `.local`, or `.localdev` domains

**Solution:**
Use `example.test` instead:
```bash
# Edit authelia/config/configuration.yml
# Change:
#   session:
#     cookies:
#       - domain: 'example.test'  # Not .localhost!

# Also update all URLs to use example.test
```

See: [BUGFIXES.md#1-cookie-domain-on-public-suffix-list](BUGFIXES.md#1-cookie-domain-on-public-suffix-list)

---

### 5. SSL Certificate Trust Issues

**Symptom:** MAS logs show "invalid peer certificate: UnknownIssuer"

**Cause:** MAS doesn't trust Caddy's self-signed CA

**Solution:**
```bash
# Extract Caddy CA certificate
docker compose -f docker-compose.local.yml exec caddy cat \
  /data/caddy/pki/authorities/local/root.crt > mas/certs/caddy-ca.crt

# Restart MAS
docker compose -f docker-compose.local.yml restart mas
```

The deploy script should do this automatically, but if you restart Caddy, you may need to re-extract the certificate.

See: [BUGFIXES.md#4-ssl-certificate-trust-issues](BUGFIXES.md#4-ssl-certificate-trust-issues)

---

### 6. Services Not Starting

**Symptom:** `docker compose ps` shows services as "Restarting" or "Exited"

**Diagnosis:**
```bash
# Check logs for the failing service
docker compose -f docker-compose.local.yml logs service-name

# Common services to check:
docker compose -f docker-compose.local.yml logs postgres
docker compose -f docker-compose.local.yml logs synapse
docker compose -f docker-compose.local.yml logs mas
docker compose -f docker-compose.local.yml logs authelia
```

**Common Causes:**
- PostgreSQL not ready before other services start
- Configuration syntax errors
- Port conflicts
- Insufficient memory

**Solutions:**
- Wait 30-60 seconds for services to stabilize
- Check for YAML syntax errors in configs
- Ensure no other services using ports 80/443
- Increase Docker memory limit if needed

---

## Maintenance

### Viewing Logs

```bash
# All services
docker compose -f docker-compose.local.yml logs -f

# Specific service
docker compose -f docker-compose.local.yml logs -f mas

# Last 100 lines
docker compose -f docker-compose.local.yml logs --tail=100 synapse
```

### Restarting Services

```bash
# Restart a single service
docker compose -f docker-compose.local.yml restart mas

# Restart all services
docker compose -f docker-compose.local.yml restart

# Stop all services
docker compose -f docker-compose.local.yml down

# Start all services
docker compose -f docker-compose.local.yml up -d
```

### Updating Configurations

After changing any configuration file:

```bash
# Restart the affected service
docker compose -f docker-compose.local.yml restart service-name
```

**Note:** For MAS upstream provider changes, you must also delete the provider from the database (see issue #2 above).

### Backing Up Data

```bash
# Create backup directory
mkdir -p backups/$(date +%Y%m%d)

# Backup databases
docker compose -f docker-compose.local.yml exec -T postgres pg_dumpall -U synapse \
  > backups/$(date +%Y%m%d)/databases.sql

# Backup configuration
cp -r authelia/config backups/$(date +%Y%m%d)/authelia-config
cp -r mas/config backups/$(date +%Y%m%d)/mas-config
cp synapse/data/homeserver.yaml backups/$(date +%Y%m%d)/

# Backup media (can be large!)
tar -czf backups/$(date +%Y%m%d)/synapse-media.tar.gz synapse/data/media_store

# Backup signing keys (CRITICAL - keep secure!)
cp mas/config/config.yaml backups/$(date +%Y%m%d)/  # Contains MAS signing key
cp authelia_private.pem backups/$(date +%Y%m%d)/   # Authelia RSA key
cp mas-signing.key backups/$(date +%Y%m%d)/        # MAS signing key
```

**Security:** Store backups in a secure location with encryption!

### Adding Users

To add additional Authelia users:

```bash
# Generate password hash
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 \
  --password 'newuserpassword'

# Edit authelia/config/users_database.yml
nano authelia/config/users_database.yml

# Add under 'users:':
# newuser:
#   displayname: "New User"
#   password: "$argon2id$..."  # Paste hash from above
#   email: newuser@matrix.example.test
#   groups:
#     - users

# Restart Authelia
docker compose -f docker-compose.local.yml restart authelia
```

### Updating Containers

```bash
# Pull latest images
docker compose -f docker-compose.local.yml pull

# Recreate containers with new images
docker compose -f docker-compose.local.yml up -d

# Remove old images
docker image prune -a
```

**Important:** Always backup before updating!

---

## Next Steps

1. ✅ **Test the full SSO flow** - Ensure authentication works
2. ✅ **Set up bridges** - Connect Telegram, WhatsApp, Signal (see [setup-bridges.sh](setup-bridges.sh))
3. ✅ **Create more users** - Add additional Authelia accounts
4. ✅ **Configure 2FA** - Mandate two-factor authentication
5. ✅ **Review security** - Read [BUGFIXES.md](BUGFIXES.md) for important notes
6. ✅ **Plan production migration** - See [PRODUCTION.md](PRODUCTION.md)
7. ✅ **Set up backups** - Schedule regular database and media backups

---

## Support Resources

- **[BUGFIXES.md](BUGFIXES.md)** - Comprehensive troubleshooting guide
- **[PRODUCTION.md](PRODUCTION.md)** - Production deployment instructions
- **[README.md](README.md)** - Quick start guide
- **Matrix Docs:** https://matrix.org/docs/
- **Synapse Docs:** https://matrix-org.github.io/synapse/
- **MAS Docs:** https://element-hq.github.io/matrix-authentication-service/
- **Authelia Docs:** https://www.authelia.com/

---

## Success Criteria

Your deployment is successful when:

- ✅ All services show "Up (healthy)" status
- ✅ Element Web loads with proper styling
- ✅ MAS pages load with CSS (not plain HTML)
- ✅ Authelia login works
- ✅ Full SSO flow completes successfully
- ✅ You can send messages in Element
- ✅ No errors in service logs

**Congratulations!** You now have a fully functional Matrix communication stack with enterprise-grade SSO authentication! 🎉
