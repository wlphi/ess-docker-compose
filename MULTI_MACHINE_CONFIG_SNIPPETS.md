# Multi-Machine Configuration Snippets

This document provides configuration snippets for deploying Matrix stack across multiple machines where Authelia and Caddy are running on separate servers.

## Key Points

✅ **All services accessible on standard HTTPS port 443**
✅ **Authelia has its own reverse proxy on Machine 2**
✅ **MAS connects to Authelia via HTTPS (not internal port 9091)**
✅ **DNS points authelia.example.com directly to Machine 2**

## Architecture

```
Machine 1: Caddy (SSL Termination)      → Port 443 (matrix, auth, element domains)
Machine 2: Authelia (SSO)               → Port 443 (authelia domain, with own reverse proxy)
Machine 3: Matrix Stack (this machine)  → Synapse, MAS, Element, PostgreSQL (internal ports)
```

**Network Flow**:
- User → `https://matrix.example.com` → Caddy (Machine 1) → Synapse (Machine 3:8008)
- User → `https://auth.example.com` → Caddy (Machine 1) → MAS (Machine 3:8080)
- User → `https://authelia.example.com` → Authelia's reverse proxy (Machine 2) → Authelia (Machine 2:9091)
- MAS → `https://authelia.example.com` → Authelia's reverse proxy (Machine 2) → Authelia (Machine 2:9091)

## Prerequisites - Generate Secrets First!

**IMPORTANT**: Before you can configure Authelia and Caddy, you must run the deploy script on the Matrix server to generate all secrets.

### Step 1: Generate Secrets on Matrix Server (Machine 3)

```bash
# On Matrix server
cd /path/to/matrix-docker-compose
./deploy.sh

# Choose:
# - Deployment: Production
# - Authelia: Yes
# - Enter your domain, IPs, email
```

The script will:
1. Generate all secure secrets (passwords, keys, tokens)
2. Create `.env` file with secrets
3. Create configuration files with secrets embedded
4. Display the admin password (SAVE THIS!)

### Step 2: Extract Secrets from Generated Files

After deploy.sh completes, you'll have these files with embedded secrets:

```bash
# On Matrix server
ls -la authelia/config/configuration.yml    # Authelia config with secrets
ls -la mas/config/config.yaml               # MAS config with CLIENT_SECRET_PLAIN
ls -la .env                                  # All environment variables
ls -la authelia_private.pem                 # RSA key for Authelia
```

### Step 3: Copy Secrets to Your Separate Servers

Now extract the secrets and copy them to the appropriate machines.

---

## How to Extract Secrets

On the Matrix server after running deploy.sh:

### Extract from `.env` file:

```bash
# On Matrix server
cat .env

# You'll see these values (copy them):
POSTGRES_PASSWORD=...
AUTHELIA_JWT_SECRET=...
AUTHELIA_SESSION_SECRET=...
AUTHELIA_STORAGE_ENCRYPTION_KEY=...
```

### Extract CLIENT_SECRET_PLAIN from MAS config:

```bash
# On Matrix server
grep "client_secret:" mas/config/config.yaml | grep -v "#"

# Output will show:
#   client_secret: 'YOUR_CLIENT_SECRET_PLAIN'
# Copy this value - you'll need it for Authelia config
```

### Get CLIENT_SECRET_HASH for Authelia:

```bash
# On Matrix server
grep "client_secret:" authelia/config/configuration.yml | grep -v "#"

# Output will show:
#   client_secret: '$pbkdf2-sha512$310000$...'
# Copy this hash - it's the hashed version of CLIENT_SECRET_PLAIN
```

### Get RSA Private Key:

```bash
# On Matrix server
cat authelia_private.pem

# Copy the entire key including:
# -----BEGIN RSA PRIVATE KEY-----
# ...
# -----END RSA PRIVATE KEY-----
```

### Get Admin Password Hash:

```bash
# On Matrix server
grep "password:" authelia/config/users_database.yml | grep -v "#"

# Output will show:
#   password: "$argon2id$v=19$m=65536,t=3,p=4$..."
# Copy this hash
```

### Admin Password (Plain Text):

The deploy script displays this once. Example output:
```
⚠ Default admin password: 58XiX7kLoRjqApEKB2GeQJJotLYHXmI7 (SAVE THIS!)
```

**SAVE THIS PASSWORD** - you'll need it to log into Authelia!

---

## Simple Copy-Paste Method

Instead of manually copying values, just copy the entire generated configs:

```bash
# On Matrix server

# Copy Authelia config to Machine 2
scp authelia/config/configuration.yml user@authelia-server:/tmp/
scp authelia/config/users_database.yml user@authelia-server:/tmp/

# Then on Authelia server, move to proper location:
sudo mv /tmp/configuration.yml /etc/authelia/
sudo mv /tmp/users_database.yml /etc/authelia/
```

This way all secrets are already embedded!

---

## Configuration for Authelia Server (Machine 2)

**Note**: Authelia should be behind your own reverse proxy (Nginx, Caddy, etc.) on port 443 with proper HTTPS certificates. The configuration below shows Authelia's internal config.

### File: `/etc/authelia/configuration.yml`

```yaml
---
# Authelia Configuration for Matrix Stack
# Machine: Authelia Server
# Note: This should be behind a reverse proxy handling HTTPS on port 443

theme: auto

server:
  address: 'tcp://0.0.0.0:9091'  # Internal port, reverse proxy forwards to this

log:
  level: 'info'
  format: 'text'

authentication_backend:
  file:
    path: '/config/users_database.yml'
    password:
      algorithm: 'argon2'
      argon2:
        variant: 'argon2id'
        iterations: 3
        memory: 65536
        parallelism: 4
        key_length: 32
        salt_length: 16

session:
  secret: 'YOUR_AUTHELIA_SESSION_SECRET'
  cookies:
    - domain: 'example.com'  # Your base domain
      authelia_url: 'https://authelia.example.com'
      default_redirection_url: 'https://element.example.com'

  redis:
    host: 'redis'  # Adjust if Redis is elsewhere
    port: 6379

storage:
  encryption_key: 'YOUR_AUTHELIA_STORAGE_ENCRYPTION_KEY'
  postgres:
    address: 'tcp://postgres:5432'  # Adjust to your PostgreSQL location
    database: 'authelia'
    username: 'synapse'
    password: 'YOUR_POSTGRES_PASSWORD'

notifier:
  filesystem:
    filename: '/config/notification.txt'

identity_validation:
  reset_password:
    jwt_secret: 'YOUR_AUTHELIA_JWT_SECRET'

access_control:
  default_policy: 'deny'
  rules:
    - domain:
        - 'matrix.example.com'
      policy: 'two_factor'
    - domain:
        - 'element.example.com'
      policy: 'two_factor'

identity_providers:
  oidc:
    hmac_secret: 'YOUR_AUTHELIA_JWT_SECRET'
    jwks:
      - key_id: 'main'
        algorithm: 'RS256'
        use: 'sig'
        key: |
          -----BEGIN RSA PRIVATE KEY-----
          YOUR_RSA_PRIVATE_KEY_HERE
          (paste content of authelia_private.pem)
          -----END RSA PRIVATE KEY-----
    clients:
      - client_id: 'mas-client'
        client_name: 'Matrix Authentication Service'
        client_secret: 'YOUR_CLIENT_SECRET_HASH'  # pbkdf2-sha512 hash
        public: false
        authorization_policy: 'two_factor'  # Require 2FA
        redirect_uris:
          - 'https://auth.example.com/oauth2/callback'
        scopes:
          - 'openid'
          - 'profile'
          - 'email'
          - 'offline_access'
        grant_types:
          - 'authorization_code'
          - 'refresh_token'
        response_types:
          - 'code'
        token_endpoint_auth_method: 'client_secret_basic'
```

### File: `/etc/authelia/users_database.yml`

```yaml
---
users:
  admin:
    displayname: "Administrator"
    password: "YOUR_ADMIN_PASSWORD_HASH"  # argon2 hash
    email: admin@example.com
    groups:
      - admins
```

### Authelia Reverse Proxy Configuration (Machine 2)

Since Authelia should be accessible on port 443, you need a reverse proxy on Machine 2. Example with Caddy:

**File: `/etc/caddy/Caddyfile` (on Authelia server)**

```caddy
{
    email YOUR_LETSENCRYPT_EMAIL
}

authelia.example.com:443 {
    reverse_proxy localhost:9091
}
```

Or with Nginx:

**File: `/etc/nginx/sites-available/authelia` (on Authelia server)**

```nginx
server {
    listen 443 ssl http2;
    server_name authelia.example.com;

    ssl_certificate /etc/letsencrypt/live/authelia.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/authelia.example.com/privkey.pem;

    location / {
        proxy_pass http://localhost:9091;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## Configuration for Caddy Server (Machine 1)

### File: `/etc/caddy/Caddyfile`

```caddy
# Caddy Configuration for Matrix Stack (Production)
# Machine: Caddy SSL Termination Server

{
    admin 0.0.0.0:2019
    email YOUR_LETSENCRYPT_EMAIL
}

# Matrix Homeserver (Synapse)
matrix.example.com:443 {
    # Well-known client endpoint
    @wk path /.well-known/matrix/client
    handle @wk {
        header Content-Type application/json
        respond `{"m.homeserver":{"base_url":"https://matrix.example.com"},"m.authentication":{"issuer":"https://auth.example.com/"}}` 200
    }

    # Well-known server endpoint (federation)
    @wk_server path /.well-known/matrix/server
    handle @wk_server {
        header Content-Type application/json
        respond `{"m.server":"matrix.example.com:443"}` 200
    }

    # Client versions endpoint with CORS
    @versions path /_matrix/client/versions
    handle @versions {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
        reverse_proxy 10.0.1.10:8008 {  # Matrix server IP
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # CORS preflight for auth metadata
    @auth_preflight {
        method OPTIONS
        path /_matrix/client/unstable/org.matrix.msc2965/auth_metadata
    }
    handle @auth_preflight {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Access-Control-Max-Age "86400"
        respond 204
    }

    # CORS preflight for all Matrix API
    @preflight {
        method OPTIONS
        path_regexp matrix ^/_matrix/.*$
    }
    handle @preflight {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Access-Control-Max-Age "86400"
        respond 204
    }

    # MAS compat endpoints (login/logout/refresh) with CORS
    @compat path \
        /_matrix/client/v3/login* \
        /_matrix/client/v3/logout* \
        /_matrix/client/v3/refresh* \
        /_matrix/client/r0/login* \
        /_matrix/client/r0/logout* \
        /_matrix/client/r0/refresh*
    handle @compat {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
        reverse_proxy 10.0.1.10:8080 {  # Matrix server IP (MAS port)
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # Everything else under /_matrix → Synapse with CORS
    @matrix_rest path_regexp matrix ^/_matrix/.*$
    handle @matrix_rest {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
        reverse_proxy 10.0.1.10:8008 {  # Matrix server IP
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # Federation endpoint
    handle /_matrix/federation/* {
        reverse_proxy 10.0.1.10:8008  # Matrix server IP
    }

    # Default: everything else → Synapse
    handle {
        reverse_proxy 10.0.1.10:8008  # Matrix server IP
    }
}

# Matrix Authentication Service (MAS)
auth.example.com:443 {
    # OIDC Discovery
    @disco path /.well-known/openid-configuration
    handle @disco {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        reverse_proxy 10.0.1.10:8080  # Matrix server IP (MAS)
    }

    # Dynamic Client Registration: CORS preflight
    @reg_opts {
        method OPTIONS
        path /oauth2/registration
    }
    handle @reg_opts {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "POST, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        respond 204
    }

    # Dynamic Client Registration (POST)
    @reg path /oauth2/registration
    route @reg {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "POST, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        reverse_proxy 10.0.1.10:8080  # Matrix server IP (MAS)
    }

    # JWKS preflight
    @jwks_opts {
        method OPTIONS
        path /oauth2/keys.json
    }
    handle @jwks_opts {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        respond 204
    }

    # Map keys.json → /oauth2/jwks
    @jwksjson path /oauth2/keys.json
    route @jwksjson {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        uri replace /oauth2/keys.json /oauth2/jwks
        reverse_proxy 10.0.1.10:8080  # Matrix server IP (MAS)
    }

    # Generic OAuth2 endpoints
    @oauth path /oauth2/*
    route @oauth {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS, POST"
        header ?Access-Control-Allow-Headers "*"
        reverse_proxy 10.0.1.10:8080  # Matrix server IP (MAS)
    }

    # Account portal
    handle_path /account/* {
        reverse_proxy 10.0.1.10:8080  # Matrix server IP (MAS)
    }

    # Authelia endpoints (proxy to Authelia server via HTTPS)
    handle_path /authelia/* {
        reverse_proxy https://authelia.example.com {
            header_up Host {upstream_hostport}
        }
    }

    # Fallback: everything else to MAS
    handle {
        reverse_proxy 10.0.1.10:8080  # Matrix server IP (MAS)
    }

    # Add CORS on error responses
    handle_errors {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Headers "*"
        header ?Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    }
}

# Authelia SSO
# Note: If Authelia runs on its own machine (Machine 2) with its own reverse proxy,
# DNS for authelia.example.com should point directly to Machine 2.
# This section is NOT needed on Caddy Machine 1. Remove this block.
#
# authelia.example.com:443 {
#     # Not needed - handled by Authelia's own reverse proxy on Machine 2
# }

# Element Web Client
element.example.com:443 {
    # Serve config.json with proper settings
    @cfg path /config.json
    handle @cfg {
        header Content-Type application/json
        header Cache-Control no-store
        respond `{
            "default_server_config": {
                "m.homeserver": {
                    "base_url": "https://matrix.example.com",
                    "server_name": "matrix.example.com"
                }
            },
            "default_server_name": "matrix.example.com",
            "disable_custom_urls": false,
            "disable_guests": true,
            "features": {
                "feature_oidc_aware_navigation": true
            }
        }` 200
    }

    # Everything else to Element container
    handle {
        reverse_proxy 10.0.1.10:80  # Matrix server IP (Element port)
    }
}
```

**Important**: Replace all IP addresses (10.0.1.10, 10.0.1.20) with your actual server IPs.

---

## DNS Configuration

Configure your DNS records to point to the correct servers:

```
matrix.example.com      A/AAAA    → Caddy Server IP (Machine 1)
element.example.com     A/AAAA    → Caddy Server IP (Machine 1)
auth.example.com        A/AAAA    → Caddy Server IP (Machine 1)
authelia.example.com    A/AAAA    → Authelia Server IP (Machine 2)
```

**Important**:
- Caddy (Machine 1) handles Matrix, Element, and MAS (auth) endpoints
- Authelia (Machine 2) handles its own domain with its own reverse proxy
- Matrix server (Machine 3) is not directly accessible from internet

---

## Deployment Steps - Complete Workflow

### Phase 1: Generate Configs on Matrix Server (Machine 3)

```bash
# On Matrix server
cd /path/to/matrix-docker-compose
./deploy.sh

# Choose:
# - Deployment type: Production
# - Include Authelia: Yes
# - Domain: example.com
# - Matrix server IP: 10.0.1.10 (this machine)
# - Authelia server IP: 10.0.1.20 (Authelia machine)
# - Email: your-email@example.com

# SAVE THE ADMIN PASSWORD shown at the end!
```

After completion, you'll have:
- `authelia/config/configuration.yml` ← Copy to Authelia server
- `authelia/config/users_database.yml` ← Copy to Authelia server
- `mas/config/config.yaml` ← Already has correct discovery_url
- `.env` ← All secrets stored here

### Phase 2: Deploy Authelia (Machine 2)

```bash
# Copy configs from Matrix server to Authelia server
scp authelia/config/configuration.yml user@10.0.1.20:/tmp/
scp authelia/config/users_database.yml user@10.0.1.20:/tmp/

# On Authelia server
sudo mkdir -p /etc/authelia
sudo mv /tmp/configuration.yml /etc/authelia/
sudo mv /tmp/users_database.yml /etc/authelia/

# Set up reverse proxy (Caddy example)
sudo tee /etc/caddy/Caddyfile << 'EOF'
{
    email your-email@example.com
}

authelia.example.com:443 {
    reverse_proxy localhost:9091
}
EOF

# Start/reload Caddy
sudo systemctl reload caddy

# Start Authelia (Docker or systemd)
docker compose up -d authelia
# OR
sudo systemctl start authelia
```

Verify Authelia is working:
```bash
curl https://authelia.example.com/.well-known/openid-configuration
# Should return JSON with OIDC endpoints
```

### Phase 3: Deploy Caddy Reverse Proxy (Machine 1)

```bash
# On Caddy server
# Copy the Caddyfile from this document (see "Configuration for Caddy Server" section)
# Update IP addresses: 10.0.1.10 and 10.0.1.20 with your actual IPs

sudo vim /etc/caddy/Caddyfile
# Paste and customize the Caddyfile configuration

# Reload Caddy
sudo caddy reload --config /etc/caddy/Caddyfile
```

Verify Caddy is proxying:
```bash
curl https://auth.example.com/.well-known/openid-configuration
# Should return MAS OIDC config
```

### Phase 4: Start Matrix Stack (Machine 3)

```bash
# On Matrix server
cd /path/to/matrix-docker-compose

# Edit docker-compose.production.yml to remove Caddy and Authelia services
# (They're running on separate machines)

# Start Matrix services
docker compose -f docker-compose.production.yml up -d

# Check services
docker compose -f docker-compose.production.yml ps
```

### Phase 5: Verify Everything Works

```bash
# From any external machine

# Test Matrix API
curl https://matrix.example.com/_matrix/client/versions

# Test MAS
curl https://auth.example.com/.well-known/openid-configuration

# Test Authelia
curl https://authelia.example.com/.well-known/openid-configuration

# Test Element
curl https://element.example.com

# All should return valid responses with Let's Encrypt certificates
```

### Phase 6: First Login

1. Open `https://element.example.com` in your browser
2. Click "Sign In"
3. You'll be redirected to Authelia
4. Login with:
   - Username: `admin`
   - Password: (the one shown during deploy.sh)
5. Set up 2FA if required
6. You'll be redirected back to Element

---

## Verification

Test each endpoint:

```bash
# From external machine
curl https://matrix.example.com/_matrix/client/versions
curl https://auth.example.com/.well-known/openid-configuration
curl https://authelia.example.com/.well-known/openid-configuration
curl https://element.example.com
```

All should return valid responses with Let's Encrypt certificates.

---

## Quick Reference: What Goes Where

### Machine 1 (Caddy - SSL Termination)

**File**: `/etc/caddy/Caddyfile`

Handles:
- `matrix.example.com` → proxies to Matrix Server (10.0.1.10:8008)
- `auth.example.com` → proxies to Matrix Server (10.0.1.10:8080 - MAS)
- `element.example.com` → proxies to Matrix Server (10.0.1.10:80 - Element)

**Note**: Does NOT handle `authelia.example.com` - that's on Machine 2

### Machine 2 (Authelia - SSO)

**Files**:
- `/etc/authelia/configuration.yml` - Authelia config with OIDC client for MAS
- `/etc/authelia/users_database.yml` - User database
- `/etc/caddy/Caddyfile` or `/etc/nginx/sites-available/authelia` - Reverse proxy for port 443

Handles:
- `authelia.example.com` on port 443
- Authelia listens internally on port 9091
- Reverse proxy forwards HTTPS (443) → localhost:9091

### Machine 3 (Matrix Stack)

**Services running**:
- Synapse (port 8008) - Matrix homeserver
- MAS (port 8080) - Authentication service
- Element (port 80) - Web client
- PostgreSQL (port 5432) - Database

**Configuration**:
- MAS configured with `discovery_url: 'https://authelia.example.com/.well-known/openid-configuration'`
- All services communicate with Authelia via public HTTPS URL
- Not directly accessible from internet (behind Caddy)

---

## Validation Checklist

After deployment, verify:

```bash
# From external machine or browser

# 1. Check Authelia OIDC discovery (should return JSON)
curl https://authelia.example.com/.well-known/openid-configuration

# 2. Check MAS OIDC discovery (should return JSON)
curl https://auth.example.com/.well-known/openid-configuration

# 3. Check Matrix well-known (should return base_url and issuer)
curl https://matrix.example.com/.well-known/matrix/client

# 4. Check Matrix versions endpoint
curl https://matrix.example.com/_matrix/client/versions

# 5. Check Element loads
curl https://element.example.com

# All should return valid responses with proper Let's Encrypt certificates
```

If any fail:
- Check DNS records point to correct IPs
- Verify firewall allows port 443
- Check reverse proxy configs
- Review Let's Encrypt certificate issuance in logs
