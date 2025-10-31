# Matrix Server Setup Guide

A step-by-step guide to deploying a complete Matrix stack with checkpoints and verification at each stage.

## What You'll Build

- **Synapse** - Matrix homeserver
- **Matrix Authentication Service (MAS)** - Modern OIDC-based authentication
- **Element Web** - Web client
- **Element Admin** - Admin interface
- **PostgreSQL** - Database backend
- **Caddy** - Reverse proxy (separate server)
- **Authelia** - Optional upstream OIDC provider

## Setup Roadmap

```
Phase 1: Preparation
├─ Prerequisites check
├─ Generate secrets
└─ ✓ Checkpoint: All secrets ready

Phase 2: Configuration
├─ Environment variables
├─ Synapse config
├─ MAS config
├─ Element config
└─ ✓ Checkpoint: All configs prepared

Phase 3: Reverse Proxy
├─ Caddy setup
├─ Optional: Authelia OIDC
└─ ✓ Checkpoint: Proxy ready

Phase 4: Deployment
├─ Start database
├─ Start services
└─ ✓ Checkpoint: All services running

Phase 5: First Login
├─ Create admin user
├─ Access Element
└─ ✓ Success: You're in!
```

---

## Prerequisites

Before starting, ensure you have:

- [ ] Docker and Docker Compose installed
- [ ] A domain name (we'll use `example.com` as placeholder)
- [ ] DNS configured:
  - `matrix.example.com` → Your server IP
  - `element.example.com` → Your server IP (or reverse proxy IP)
- [ ] If using Authelia: separate Authelia server at `auth.example.com`
- [ ] Terminal access to your server

### Architecture Overview

```
User → Caddy (reverse proxy) → Synapse/MAS/Element
                                    ↓
                              PostgreSQL
                                    ↓
                          Authelia (optional)
```

---

# Phase 1: Preparation

## Step 1: Clone Repository and Setup

```bash
git clone <your-repo-url>
cd matrix-docker-compose

# Copy environment template
cp templates/.env.template .env
```

**✓ Verify:** You should now have a `.env` file in your directory.

```bash
ls -la .env
```

## Step 2: Generate Secrets

**IMPORTANT:** Save all generated secrets in a secure location. You'll need them in the next steps.

### 2a. Database Password

```bash
openssl rand -base64 24 | tr -d "=+/" | cut -c1-32
```

**Expected output:** A 32-character alphanumeric string like `Kx8mN2pQ7vR4tY6wZ9aB5cD1eF3gH8j`

Save this as: `POSTGRES_PASSWORD`

### 2b. Synapse Registration Secret

```bash
openssl rand -base64 32 | tr -d "=+/"
```

**Expected output:** A long base64 string like `mLpNqRsTuVwXyZaBcDeFgHiJkLmNoPqRsTuVwXyZ`

Save this as: `SYNAPSE_REGISTRATION_SHARED_SECRET`

### 2c. MAS Encryption Secret

```bash
openssl rand -hex 32
```

**Expected output:** Exactly 64 hexadecimal characters like `a1b2c3d4e5f6...` (must be 64 chars)

Save this as: `MAS_SECRETS_ENCRYPTION`

### 2d. MAS Keys Secret

```bash
openssl rand -hex 32
```

**Expected output:** Exactly 64 hexadecimal characters (different from above)

Save this as: `MAS_SECRETS_KEYS`

### 2e. OIDC Client Secret (Optional - only if using Authelia)

```bash
openssl rand -base64 32 | tr -d "=+/"
```

**Expected output:** A long base64 string

Save this as: `AUTHELIA_CLIENT_SECRET`

### ✓ Checkpoint: Preparation Complete

You should now have:
- [ ] Repository cloned
- [ ] `.env` file created
- [ ] 4-5 secrets generated and saved
- [ ] Secrets are in a secure location (password manager recommended)

---

# Phase 2: Configuration

## Step 3: Configure Environment Variables

Open your `.env` file:

```bash
nano .env
```

Fill in these values (copy from your saved secrets):

| Variable | Example Value | Your Secret |
|----------|---------------|-------------|
| `MATRIX_DOMAIN` | `matrix.example.com` | Your domain |
| `ELEMENT_DOMAIN` | `element.example.com` | Your domain |
| `POSTGRES_PASSWORD` | From Step 2a | ____________ |
| `SYNAPSE_REGISTRATION_SHARED_SECRET` | From Step 2b | ____________ |
| `MAS_SECRETS_ENCRYPTION` | From Step 2c (64 hex) | ____________ |
| `MAS_SECRETS_KEYS` | From Step 2d (64 hex) | ____________ |
| `AUTHELIA_CLIENT_SECRET` | From Step 2e (optional) | ____________ |

Save and exit (`Ctrl+X`, then `Y`, then `Enter` in nano).

**✓ Verify:** Check that all placeholders are replaced:

```bash
grep "CHANGE_ME" .env
```

**Expected output:** Nothing (no output means all placeholders are filled)

## Step 4: Configure Synapse

### 4a. Create config directory and copy template

```bash
mkdir -p synapse/config
cp templates/homeserver.yaml synapse/config/homeserver.yaml
```

### 4b. Replace placeholders

Open the file:

```bash
nano synapse/config/homeserver.yaml
```

Find and replace these placeholders:

| Placeholder | Replace With | Notes |
|-------------|--------------|-------|
| `{{MATRIX_DOMAIN}}` | `matrix.example.com` | Your Matrix domain |
| `{{POSTGRES_PASSWORD}}` | Your DB password | **MUST match .env** |
| `{{SYNAPSE_REGISTRATION_SHARED_SECRET}}` | Your registration secret | From Step 2b |

Save and exit.

**⚠️ CRITICAL:** The database password here MUST exactly match what you put in `.env`!

**✓ Verify:** Check no placeholders remain:

```bash
grep "{{" synapse/config/homeserver.yaml
```

**Expected output:** Nothing (no matches)

## Step 5: Configure MAS (Matrix Authentication Service)

### 5a. Create config and copy template

```bash
mkdir -p mas/config
cp templates/mas-config.yaml mas/config/config.yaml
```

### 5b. Replace placeholders

Open the file:

```bash
nano mas/config/config.yaml
```

Replace these placeholders:

| Placeholder | Replace With |
|-------------|--------------|
| `{{MATRIX_DOMAIN}}` | `matrix.example.com` |
| `{{POSTGRES_PASSWORD}}` | Your DB password (**must match**) |
| `{{MAS_SECRETS_ENCRYPTION}}` | Your 64-char hex from Step 2c |
| `{{MAS_SECRETS_KEYS}}` | Your 64-char hex from Step 2d |

**If using Authelia:**

| Placeholder | Replace With |
|-------------|--------------|
| `{{AUTHELIA_URL}}` | `https://auth.example.com` |
| `{{AUTHELIA_CLIENT_ID}}` | `matrix_mas` (or your choice) |
| `{{AUTHELIA_CLIENT_SECRET}}` | From Step 2e |

Uncomment the `upstream_oauth2` section.

**If NOT using Authelia:**

Find the `upstream_oauth2` section and comment it out or delete it entirely.

Save and exit.

**✓ Verify:** Check configuration:

```bash
# No placeholders should remain
grep "{{" mas/config/config.yaml

# Verify secret lengths (should be exactly 64 characters each)
grep "encryption:" mas/config/config.yaml
grep "key:" mas/config/config.yaml
```

## Step 6: Configure Element Web

### 6a. Create config and copy template

```bash
mkdir -p element/config
cp templates/element-config.json element/config/config.json
```

### 6b. Replace placeholders

Open the file:

```bash
nano element/config/config.json
```

Replace:
- `{{MATRIX_DOMAIN}}` → `matrix.example.com`
- `{{ELEMENT_DOMAIN}}` → `element.example.com`

Save and exit.

**✓ Verify:**

```bash
grep "{{" element/config/config.json
```

**Expected output:** Nothing

### ✓ Checkpoint: Configuration Complete

You should now have:
- [ ] `.env` configured with all secrets
- [ ] `synapse/config/homeserver.yaml` configured
- [ ] `mas/config/config.yaml` configured
- [ ] `element/config/config.json` configured
- [ ] No `{{placeholders}}` remain in any file
- [ ] Database password matches in all 3 files (.env, homeserver.yaml, mas-config.yaml)

---

# Phase 3: Reverse Proxy Setup

## Step 7: Configure Caddy

### Option A: Caddy on Same Server

```bash
mkdir -p caddy
cp templates/Caddyfile caddy/Caddyfile
nano caddy/Caddyfile
```

Replace:
- `{{MATRIX_DOMAIN}}` → `matrix.example.com`
- `{{ELEMENT_DOMAIN}}` → `element.example.com`
- Update email in global options (line 4)

Leave `localhost` URLs as-is.

### Option B: Caddy on Separate Server

1. Copy template to your Caddy server:
   ```bash
   scp templates/Caddyfile user@caddy-server:/etc/caddy/Caddyfile
   ```

2. On the Caddy server, edit the file:
   ```bash
   nano /etc/caddy/Caddyfile
   ```

3. Replace placeholders:
   - `{{MATRIX_DOMAIN}}` → `matrix.example.com`
   - `{{ELEMENT_DOMAIN}}` → `element.example.com`
   - `localhost` → Your Matrix server IP (e.g., `192.168.1.100`)
   - Update email address

4. Update firewall on Matrix server:
   ```bash
   # Allow Caddy server to access Matrix services
   sudo ufw allow from CADDY_SERVER_IP to any port 8008
   sudo ufw allow from CADDY_SERVER_IP to any port 8080
   sudo ufw allow from CADDY_SERVER_IP to any port 8082
   ```

**✓ Verify:** Check Caddyfile syntax:

```bash
# If Caddy is installed locally
caddy validate --config caddy/Caddyfile

# Or just check for placeholders
grep "{{" caddy/Caddyfile
```

**Expected output:** No placeholders remain

## Step 8: Configure Authelia OIDC (Optional)

**Skip this step if you're NOT using Authelia.**

### 8a. On your Authelia server, open config:

```bash
nano /etc/authelia/configuration.yml
```

### 8b. Find the `identity_providers.oidc.clients` section and add:

Use the template from `templates/authelia-client.yml` as a guide.

Key points:
- `client_id`: Must match what you put in MAS config (e.g., `matrix_mas`)
- `client_secret`: Must be hashed with pbkdf2
- `redirect_uris`: Must be `https://matrix.example.com/oauth2/callback`

### 8c. Hash your client secret:

```bash
authelia crypto hash generate pbkdf2 --password 'YOUR_CLIENT_SECRET_FROM_STEP_2E'
```

**Expected output:** A hash like `$pbkdf2-sha512$310000$...`

Copy this hash into your Authelia config as `client_secret`.

### 8d. Restart Authelia:

```bash
docker restart authelia
# or
systemctl restart authelia
```

**✓ Verify:** Check Authelia logs for startup errors:

```bash
docker logs authelia | tail -20
```

**Expected:** No OIDC configuration errors

### ✓ Checkpoint: Reverse Proxy Ready

You should now have:
- [ ] Caddyfile configured with your domains
- [ ] If separate server: firewall rules configured
- [ ] If using Authelia: OIDC client configured and Authelia restarted
- [ ] No syntax errors in configurations

---

# Phase 4: Deployment

## Step 9: Start the Stack

### 9a. Create data directories

```bash
mkdir -p synapse/data mas/data element-admin/data postgres/data
```

**✓ Verify:**

```bash
ls -la | grep -E "synapse|mas|element-admin|postgres"
```

You should see all four directories.

### 9b. Start PostgreSQL first

```bash
docker compose up -d postgres
```

**Expected output:**

```
[+] Running 1/1
 ✓ Container matrix-postgres  Started
```

### 9c. Wait for database to initialize

```bash
echo "Waiting for PostgreSQL to be ready..."
sleep 15
```

### 9d. Verify database is ready

```bash
docker compose exec postgres pg_isready -U synapse
```

**Expected output:**

```
/var/run/postgresql:5432 - accepting connections
```

If you see this, continue. If not, wait another 10 seconds and try again.

### 9e. Start all services

```bash
docker compose up -d
```

**Expected output:**

```
[+] Running 5/5
 ✓ Container matrix-postgres       Running
 ✓ Container matrix-synapse        Started
 ✓ Container matrix-mas            Started
 ✓ Container matrix-element        Started
 ✓ Container matrix-element-admin  Started
```

### 9f. Monitor startup logs

```bash
docker compose logs -f
```

Watch for:
- ✓ Synapse: "Synapse now listening on port 8008"
- ✓ MAS: "Listening on 0.0.0.0:8080"
- ✓ No database connection errors
- ✓ No "invalid secret length" errors

Press `Ctrl+C` to exit log view (services keep running).

## Step 10: Verify Services

### 10a. Check service status

```bash
docker compose ps
```

**Expected output:** All services should show "Up" or "Up (healthy)":

```
NAME                    STATUS
matrix-element          Up
matrix-element-admin    Up
matrix-mas              Up (healthy)
matrix-postgres         Up (healthy)
matrix-synapse          Up (healthy)
```

If any service shows "Restarting" or "Exited", check logs:

```bash
docker compose logs SERVICE_NAME
```

### 10b. Test Synapse API

```bash
curl https://matrix.example.com/_matrix/client/versions
```

**Expected output:** JSON response with version information:

```json
{
  "versions": ["r0.0.1", "r0.1.0", ...],
  "unstable_features": { ... }
}
```

If you get an error, check:
- DNS is correctly configured
- Caddy is running and proxying correctly
- Firewall allows traffic

### 10c. Test Element Web

```bash
curl -I https://element.example.com/
```

**Expected output:** HTTP 200 OK with HTML content type

### 10d. Test MAS health

```bash
curl http://localhost:8080/health
```

**Expected output:**

```json
{
  "status": "ok"
}
```

### ✓ Checkpoint: Deployment Complete

You should now have:
- [ ] All 5 containers running
- [ ] All health checks passing
- [ ] Synapse API responding
- [ ] Element Web accessible
- [ ] MAS health check passing
- [ ] No errors in logs

---

# Phase 5: First Login

## Step 11: Create Your First Admin User

### 11a. Run the user registration command

```bash
docker compose exec mas mas-cli manage register-user \
  --username admin \
  --admin
```

**Expected interaction:**

```
? Enter the password for the user: ****
? Confirm the password: ****
User admin registered successfully!
```

**⚠️ IMPORTANT:** Save this password securely! This is your admin account.

### 11b. Verify user creation

```bash
docker compose exec mas mas-cli manage list-users
```

**Expected output:**

```
Username: admin
Admin: true
...
```

## Step 12: Access Element Web

### 12a. Open Element in your browser

Navigate to: `https://element.example.com`

**✓ You should see:** Element Web welcome screen

### 12b. Sign in

1. Click **"Sign In"**
2. **You should be redirected to:** `https://matrix.example.com` (MAS login page)

**If using Authelia:**
3. Click **"Sign in with Authelia"** (or your provider name)
4. **You should be redirected to:** `https://auth.example.com`
5. Enter your Authelia credentials
6. Complete 2FA if required
7. **You should be redirected back to:** Element Web

**If NOT using Authelia:**
3. Enter username: `admin`
4. Enter password: (from Step 11a)
5. Click **"Sign In"**

### 12c. Confirm successful login

**✓ You should see:**
- Element Web interface loaded
- Your username in the top left
- Ability to create or join rooms

## Step 13: Access Element Admin

### 13a. Open admin interface

Navigate to: `http://YOUR_SERVER_IP:8081`

**⚠️ Security Note:** This interface has no authentication by default. Restrict access by IP in production!

### 13b. Connect to homeserver

1. Enter homeserver URL: `https://matrix.example.com`
2. Enter username: `admin`
3. Enter password: (from Step 11a)
4. Click **"Sign In"**

**✓ You should see:**
- Admin dashboard loaded
- Server statistics
- User management interface
- Ability to view rooms, users, and server config

### ✓ Success! Setup Complete

Congratulations! You now have:
- [ ] A fully functional Matrix homeserver
- [ ] Element Web client accessible
- [ ] Admin account created
- [ ] Successfully logged in
- [ ] Admin interface accessible

---

# What's Next?

## Recommended Next Steps

1. **Create additional users:**
   ```bash
   docker compose exec mas mas-cli manage register-user --username USERNAME
   ```

2. **Enable user registration** (optional):
   Edit `mas/config/config.yaml` and set `registration.enabled: true`

3. **Set up backups:**
   See [Maintenance](#maintenance) section below

4. **Configure federation:**
   See [Advanced Configuration](#advanced-configuration) below

5. **Restrict admin interface access:**
   Configure Caddy to proxy Element Admin with IP restrictions

## Testing Your Setup

### Create a test room

1. In Element Web, click the **"+"** next to "Rooms"
2. Create a new room
3. Send a test message

**✓ Success if:** Message appears and is stored

### Test user registration (if enabled)

1. Logout from Element
2. Click **"Create Account"**
3. Follow registration flow

**✓ Success if:** New user can be created and login

---

# Troubleshooting

## Quick Diagnostics

Run this command to check common issues:

```bash
# Check all services
docker compose ps

# Check recent logs for errors
docker compose logs --tail=50 | grep -i error

# Verify database connectivity
docker compose exec postgres pg_isready -U synapse

# Verify MAS health
curl http://localhost:8080/health

# Verify Synapse API
curl https://matrix.example.com/_matrix/client/versions
```

## Common Issues

### Issue: Services fail to connect to database

**Symptom:** Logs show "could not connect to database" or similar

**Solution:**

1. Check PostgreSQL is running:
   ```bash
   docker compose ps postgres
   ```

2. Verify password matches in all configs:
   ```bash
   grep POSTGRES_PASSWORD .env
   grep "password:" synapse/config/homeserver.yaml
   grep "postgresql://" mas/config/config.yaml
   ```

3. Restart services:
   ```bash
   docker compose restart synapse mas
   ```

### Issue: MAS fails with "invalid secret length"

**Symptom:** MAS container keeps restarting with secret length error

**Solution:**

1. Verify secrets are exactly 64 hex characters:
   ```bash
   # Count characters (should output: 64)
   echo -n "YOUR_SECRET" | wc -c
   ```

2. Regenerate if needed:
   ```bash
   openssl rand -hex 32
   ```

3. Update `mas/config/config.yaml`

4. Restart MAS:
   ```bash
   docker compose restart mas
   ```

### Issue: Cannot create users

**Symptom:** `mas-cli register-user` command fails

**Solution:**

1. Check MAS logs:
   ```bash
   docker compose logs mas | tail -50
   ```

2. Verify MAS can reach Synapse:
   ```bash
   docker compose exec mas curl http://synapse:8008/_matrix/client/versions
   ```
   **Expected:** JSON response

3. Check database migrations completed:
   ```bash
   docker compose logs mas | grep migration
   ```
   **Expected:** Should see migration success messages

### Issue: OIDC login fails (Authelia)

**Symptom:** Redirect to Authelia works, but login doesn't complete

**Solution:**

1. Verify redirect URI matches exactly:
   - In Authelia: `https://matrix.example.com/oauth2/callback`
   - In MAS config: Should match

2. Check client_id matches between MAS and Authelia

3. Verify client_secret:
   - Plaintext in MAS config
   - Hashed with pbkdf2 in Authelia config

4. Check Authelia logs:
   ```bash
   docker logs authelia | grep -i error
   ```

5. Test network connectivity:
   ```bash
   docker compose exec mas curl -v https://auth.example.com/.well-known/openid-configuration
   ```
   **Expected:** OIDC configuration JSON

### Issue: Element shows "Cannot connect to homeserver"

**Symptom:** Element Web loads but shows connection error

**Solution:**

1. Check Element config has correct homeserver URL:
   ```bash
   grep base_url element/config/config.json
   ```
   **Expected:** `"base_url": "https://matrix.example.com"`

2. Verify Caddy is proxying correctly:
   ```bash
   curl -v https://matrix.example.com/_matrix/client/versions
   ```
   **Expected:** 200 OK with JSON response

3. Check CORS headers:
   ```bash
   curl -v -H "Origin: https://element.example.com" \
     https://matrix.example.com/_matrix/client/versions
   ```
   **Expected:** Should include `Access-Control-Allow-Origin` header

4. Check browser console:
   - Open browser DevTools (F12)
   - Look for specific error messages

### Issue: Port conflicts

**Symptom:** Docker fails to start with "port already in use"

**Solution:**

1. Find what's using the ports:
   ```bash
   sudo netstat -tlnp | grep -E '8008|8080|8082|8081|5432'
   ```

2. Either:
   - Stop the conflicting service, or
   - Modify ports in `docker-compose.yml`

### Issue: Caddy can't get certificates

**Symptom:** Caddy logs show ACME/Let's Encrypt errors

**Solution:**

1. Verify DNS points to your server:
   ```bash
   dig matrix.example.com
   dig element.example.com
   ```

2. Ensure ports 80 and 443 are open:
   ```bash
   sudo netstat -tlnp | grep -E ':80|:443'
   ```

3. Check Caddy logs:
   ```bash
   docker logs caddy | grep -i error
   ```

4. For testing, use staging certificates:
   - Add to Caddyfile: `acme_ca https://acme-staging-v02.api.letsencrypt.org/directory`

---

# Maintenance

## Backing Up

### Database Backup

```bash
# Full database dump
docker compose exec postgres pg_dump -U synapse synapse > backup-$(date +%Y%m%d).sql

# Verify backup
ls -lh backup-*.sql
```

### Data Backup

```bash
# Backup all persistent data
tar -czf matrix-backup-$(date +%Y%m%d).tar.gz \
  postgres/data \
  synapse/data \
  mas/data \
  .env \
  synapse/config \
  mas/config \
  element/config

# Verify backup
ls -lh matrix-backup-*.tar.gz
```

### Automated Backups

Create a cron job:

```bash
crontab -e
```

Add this line for daily backups at 2 AM:

```
0 2 * * * cd /path/to/matrix-docker-compose && /path/to/backup-script.sh
```

## Updating

### Update Docker Images

```bash
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Check logs for any issues
docker compose logs -f
```

### Update Configuration

After changing any config file:

```bash
# Restart affected service
docker compose restart synapse

# Or restart all
docker compose restart
```

## Monitoring

### Check Service Health

```bash
# Quick status
docker compose ps

# Detailed stats
docker stats

# Check disk usage
docker system df
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs synapse -f --tail=100

# Search for errors
docker compose logs | grep -i error
```

### Database Maintenance

```bash
# Check database size
docker compose exec postgres psql -U synapse -c "SELECT pg_size_pretty(pg_database_size('synapse'));"

# Vacuum database (optimize)
docker compose exec postgres psql -U synapse -c "VACUUM ANALYZE;"
```

## Changing Database Password

**⚠️ CRITICAL:** Follow these steps exactly:

1. Stop all services:
   ```bash
   docker compose down
   ```

2. Update password in `.env`

3. Update password in `synapse/config/homeserver.yaml`

4. Update password in `mas/config/config.yaml`

5. Start PostgreSQL only:
   ```bash
   docker compose up -d postgres
   ```

6. Change password in PostgreSQL:
   ```bash
   docker compose exec postgres psql -U synapse -c "ALTER USER synapse PASSWORD 'NEW_PASSWORD';"
   ```

7. Start all services:
   ```bash
   docker compose up -d
   ```

8. Verify all services connected:
   ```bash
   docker compose logs | grep -i "database"
   ```

---

# Advanced Configuration

## Federation

To federate with other Matrix servers:

### 1. Configure DNS SRV Record

Add this DNS record:

```
_matrix._tcp.example.com. 3600 IN SRV 10 0 443 matrix.example.com.
```

### 2. Verify Federation

```bash
# Test federation (replace with your domain)
curl https://matrix.example.com/.well-known/matrix/server
```

**Expected output:**

```json
{
  "m.server": "matrix.example.com:443"
}
```

### 3. Test with Federation Tester

Visit: https://federationtester.matrix.org/

Enter your domain: `matrix.example.com`

**✓ Success if:** All checks pass

## User Registration

### Enable Public Registration

Edit `mas/config/config.yaml`:

```yaml
registration:
  enabled: true
  require_email: false  # Set to true if you want email verification
```

Restart MAS:

```bash
docker compose restart mas
```

### Email Verification (Optional)

Configure email in `mas/config/config.yaml`:

```yaml
email:
  from: "noreply@matrix.example.com"
  reply_to: "support@matrix.example.com"
  transport: smtp
  smtp:
    mode: plain
    hostname: "smtp.example.com"
    port: 587
    username: "noreply@matrix.example.com"
    password: "smtp_password"
```

## Custom Element Themes

1. Create themes directory:
   ```bash
   mkdir -p element/config/themes
   ```

2. Add theme files to the directory

3. Update `element/config/config.json`:
   ```json
   "setting_defaults": {
     "custom_themes": [
       {
         "name": "My Theme",
         "is_dark": true,
         "colors": { ... }
       }
     ]
   }
   ```

4. Restart Element:
   ```bash
   docker compose restart element
   ```

---

# Security Considerations

## Production Checklist

- [ ] All secrets are strong and randomly generated
- [ ] `.env` file is not committed to version control
- [ ] Database password matches in all config files
- [ ] Firewall configured (only ports 80, 443 exposed to internet)
- [ ] Element Admin access restricted by IP
- [ ] SSL/TLS certificates are valid (Let's Encrypt)
- [ ] Automated backups configured
- [ ] Monitoring and alerting set up
- [ ] Docker images regularly updated
- [ ] Rate limiting configured in Caddy
- [ ] If using Authelia: 2FA enabled

## Hardening Tips

1. **Restrict Element Admin:**
   Add IP restrictions in Caddy (see template comments)

2. **Enable 2FA in Authelia:**
   Require TOTP for all users

3. **Monitor failed login attempts:**
   ```bash
   docker compose logs mas | grep -i "failed login"
   ```

4. **Set up fail2ban:**
   Monitor Caddy logs for suspicious activity

5. **Regular security updates:**
   ```bash
   # Weekly update routine
   docker compose pull
   docker compose up -d
   ```

---

# Support & Resources

## Documentation

- **Synapse:** https://element-hq.github.io/synapse/
- **MAS:** https://element-hq.github.io/matrix-authentication-service/
- **Element:** https://github.com/element-hq/element-web
- **Caddy:** https://caddyserver.com/docs/
- **Authelia:** https://www.authelia.com/

## Getting Help

1. **Check troubleshooting section above**
2. **Review logs:** `docker compose logs SERVICE_NAME`
3. **Verify configuration:** Check for typos and placeholder values
4. **Open an issue:** In this repository with logs and config (redact secrets!)

## License

This setup guide and templates are provided as-is for self-hosting Matrix servers.

Component licenses:
- Matrix Synapse: Apache 2.0
- Matrix Authentication Service: Apache 2.0
- Element Web: Apache 2.0
- PostgreSQL: PostgreSQL License
- Caddy: Apache 2.0
