# Matrix Stack Bugfixes & Lessons Learned

This document captures all the critical issues encountered during deployment and their solutions. These are things that are **not clearly documented** in the official documentation.

## Table of Contents
1. [Cookie Domain on Public Suffix List](#1-cookie-domain-on-public-suffix-list)
2. [MAS Missing Assets Resource](#2-mas-missing-assets-resource)
3. [MAS Not Fetching Userinfo](#3-mas-not-fetching-userinfo)
4. [SSL Certificate Trust Issues](#4-ssl-certificate-trust-issues)
5. [Authelia Redirect URI Configuration](#5-authelia-redirect-uri-configuration)
6. [Claims Template Compatibility](#6-claims-template-compatibility)
7. [MAS Database Caching](#7-mas-database-caching)
8. [MAS Discovery URL for Internal Communication](#8-mas-discovery-url-for-internal-communication)
9. [PostgreSQL Data Persistence Across Deployments](#9-postgresql-data-persistence-across-deployments)

---

## 1. Cookie Domain on Public Suffix List

### Problem
Authelia rejects cookie domains that are on the [Public Suffix List](https://publicsuffix.org/), including:
- `.localhost`
- `.local`
- `.localdev`

### Error Message
```
level=error msg="Configuration: session: domain config #1 (domain '.localhost'): option 'domain' is not a valid cookie domain: the domain is part of the special public suffix list"
```

### Solution
Use a fake TLD that's not on the public suffix list, such as:
- `example.test` (recommended for local development)
- `example.internal`
- `example.dev` (but be aware `.dev` requires HTTPS)

### Configuration
```yaml
# authelia/config/configuration.yml
session:
  cookies:
    - domain: 'example.test'  # Not .example.test for subdomains!
      authelia_url: 'https://authelia.example.test'
```

### Why Not Documented
The official Authelia docs mention the public suffix list but don't clearly list which common development TLDs are affected.

---

## 2. MAS Missing Assets Resource

### Problem
MAS serves HTML pages but CSS/JS assets return 404, causing unstyled pages.

### Error Message
```
WARN http.server.response GET-22 - "GET /assets/shared-CVCHz34K.css HTTP/1.1" 404 Not Found
WARN http.server.response GET-23 - "GET /assets/templates-CyDybuwN.css HTTP/1.1" 404 Not Found
```

### Root Cause
The MAS HTTP listener configuration is missing the `assets` resource.

### Solution
Add the `assets` resource to the MAS configuration:

```yaml
# mas/config/config.yaml
http:
  listeners:
    - name: web
      resources:
        - name: discovery
        - name: human
        - name: oauth
        - name: compat
        - name: graphql
          playground: true
        - name: assets    # ← Critical: This is required!
        - name: adminapi  # ← Required for Element Admin panel
      binds:
        - address: '[::]:8080'
```

### Verification
Test asset availability:
```bash
curl -I https://auth.example.test/assets/shared-CVCHz34K.css
# Should return: HTTP/2 200
```

### Why Not Documented
The MAS documentation mentions the assets resource but doesn't emphasize it's **mandatory** for proper UI rendering. Many configuration examples omit it.

### Assets Location
- Container path: `/usr/local/share/mas-cli/assets/`
- This path is automatically configured by MAS

---

## 3. MAS Not Fetching Userinfo

### Problem
Templates render to empty strings even though claims are configured correctly.

### Error Message
```
ERROR mas_handlers::upstream_oauth2::link:131 POST-102 - Template "{{ user.preferred_username }}" rendered to an empty string
```

### Root Cause
MAS defaults to reading claims **only from the ID token**, not from the userinfo endpoint. Authelia provides most user claims via userinfo, not in the ID token.

### Solution
Enable userinfo fetching in MAS upstream OAuth2 provider configuration:

```yaml
# mas/config/config.yaml
upstream_oauth2:
  providers:
    - id: '01HQW90Z35CMXFJWQPHC3BGZGQ'
      issuer: 'https://authelia.example.test'
      client_id: 'mas-client'
      client_secret: 'your-secret'
      scope: 'openid profile email offline_access'
      token_endpoint_auth_method: 'client_secret_basic'
      fetch_userinfo: true    # ← Critical: Must be enabled!
      claims_imports:
        localpart:
          action: force
          template: '{{ user.preferred_username }}'
```

### Why Not Documented
The MAS documentation doesn't clearly state that `fetch_userinfo` defaults to `false` and that most OIDC providers (including Authelia) serve user claims via userinfo, not in the ID token.

### Testing
Check the database to verify the setting:
```sql
SELECT upstream_oauth_provider_id, fetch_userinfo FROM upstream_oauth_providers;
```
Should show `t` (true).

---

## 4. SSL Certificate Trust Issues

### Problem
MAS cannot fetch Authelia's OIDC metadata when using self-signed certificates behind Caddy.

### Error Message
```
ERROR mas_handlers::upstream_oauth2::cache - Failed to fetch provider metadata issuer=https://authelia.example.test error=invalid peer certificate: UnknownIssuer
```

### Root Cause
MAS doesn't trust Caddy's self-signed CA certificate.

### Solution (Local Development)
1. Extract Caddy's CA certificate:
```bash
docker compose exec caddy cat /data/caddy/pki/authorities/local/root.crt > mas/certs/caddy-ca.crt
```

2. Mount the certificate in the MAS container:
```yaml
# docker-compose.local.yml
services:
  mas:
    environment:
      SSL_CERT_FILE: /certs/caddy-ca.crt
    volumes:
      - ./mas/certs:/certs:ro
```

3. Restart MAS to apply:
```bash
docker compose restart mas
```

### Solution (Production with Let's Encrypt)
Not needed - production deployments use Let's Encrypt certificates which are already trusted.

### Alternative (Local Development)
Use internal HTTP endpoint with `discovery_url`:
```yaml
upstream_oauth2:
  providers:
    - issuer: 'https://authelia.example.test'
      discovery_url: 'http://authelia:9091/.well-known/openid-configuration'
```
**Note:** This only works if the Authelia OIDC issuer accepts HTTP for discovery.

### Why Not Documented
The MAS documentation doesn't mention the `SSL_CERT_FILE` environment variable or how to handle self-signed certificates in development.

---

## 5. Authelia Redirect URI Configuration

### Problem
OAuth flow fails with redirect URI mismatch error.

### Error Message
```
Fehler: invalid_request
Beschreibung: The 'redirect_uri' parameter does not match any of the OAuth 2.0 Client's pre-registered 'redirect_uris'.
```

### Root Cause
Authelia requires the exact redirect URI to be pre-registered, but MAS generates different callback URIs depending on context:
- Standard: `https://auth.example.test/callback`
- OAuth2: `https://auth.example.test/oauth2/callback`
- Upstream provider: `https://auth.example.test/upstream/callback/{provider_id}`

The provider ID in the database may differ from the config file ID.

### Solution
Add ALL possible redirect URIs to Authelia client configuration:

```yaml
# authelia/config/configuration.yml
identity_providers:
  oidc:
    clients:
      - client_id: 'mas-client'
        redirect_uris:
          - 'https://auth.example.test/callback'
          - 'https://auth.example.test/oauth2/callback'
          - 'https://auth.example.test/upstream/callback/01HQW90Z35CMXFJWQPHC3BGZGQ'  # Config file ID
          - 'https://auth.example.test/upstream/callback/018df890-7c65-653a-f972-f68b06b87e17'  # Database ID
```

### Finding the Provider ID
```sql
-- Connect to MAS database
docker compose exec postgres psql -U synapse -d mas

-- Get provider ID
SELECT upstream_oauth_provider_id FROM upstream_oauth_providers;
```

### Why Not Documented
Neither MAS nor Authelia documentation clearly explains that MAS may generate different provider IDs between config and database, or that the upstream callback pattern requires the provider ID.

---

## 6. Claims Template Compatibility

### Problem
Claims templates render to empty strings when using Authelia as the upstream provider.

### Root Cause
Authelia provides different claims than expected. Testing revealed:
- `{{ user.name }}` — not provided by Authelia
- `{{ user.preferred_username }}` — works (contains username)
- `{{ user.email }}` — works

### Solution
Use `preferred_username` for localpart and displayname:

```yaml
# mas/config/config.yaml
upstream_oauth2:
  providers:
    - claims_imports:
        localpart:
          action: force
          template: '{{ user.preferred_username }}'  # ← Use this
        displayname:
          action: suggest
          template: '{{ user.preferred_username }}'  # ← Not {{ user.name }}
        email:
          action: force
          template: '{{ user.email }}'
          set_email_verification: always
```

### Testing Claims
To discover available claims, temporarily enable debug logging in MAS or check Authelia's userinfo endpoint:
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" https://authelia.example.test/api/oidc/userinfo
```

### Why Not Documented
The MAS documentation uses `{{ user.name }}` in examples, but this claim is not standardized in OIDC and many providers (including Authelia) don't provide it.

---

## 7. MAS Database Caching

### Problem
After updating MAS configuration, changes to upstream OAuth2 providers don't take effect even after restart.

### Root Cause
MAS caches provider configuration in PostgreSQL. Changes to `config.yaml` are only synced when:
- MAS starts for the first time
- The provider doesn't exist in the database
- Explicit sync is forced

### Solution
Delete the provider from the database to force a re-sync:

```sql
-- Connect to MAS database
docker compose exec postgres psql -U synapse -d mas

-- Find provider ID
SELECT upstream_oauth_provider_id FROM upstream_oauth_providers;

-- Delete provider (CASCADE deletes related records)
DELETE FROM upstream_oauth_authorization_sessions WHERE upstream_oauth_provider_id = 'provider-id-here';
DELETE FROM upstream_oauth_links WHERE upstream_oauth_provider_id = 'provider-id-here';
DELETE FROM upstream_oauth_providers WHERE upstream_oauth_provider_id = 'provider-id-here';

-- Exit and restart MAS
\q
docker compose restart mas
```

### Verification
Check that the provider was re-created:
```bash
docker compose logs mas | grep "Adding provider"
# Should show: INFO mas_cli::sync:198 Adding provider provider.id=...
```

### Why Not Documented
The MAS documentation doesn't clearly explain that provider configuration is cached in the database and must be manually deleted to apply config changes.

### Alternative
Use MAS CLI to force sync (if available):
```bash
docker compose exec mas mas-cli config sync
```

---

## 8. MAS Discovery URL for Internal Communication

### Problem
When MAS and Authelia are in the same Docker network, MAS tries to fetch OIDC metadata over HTTPS through the external reverse proxy, adding unnecessary latency and SSL complexity.

### Solution
Use `discovery_url` to specify an internal HTTP endpoint:

```yaml
# mas/config/config.yaml
upstream_oauth2:
  providers:
    - id: '01HQW90Z35CMXFJWQPHC3BGZGQ'
      issuer: 'https://authelia.example.test'  # Public issuer URL
      discovery_url: 'http://authelia:9091/.well-known/openid-configuration'  # Internal discovery
      client_id: 'mas-client'
```

### Benefits
- Faster metadata fetching (internal network)
- No SSL certificate trust issues
- Reduces external traffic through reverse proxy

### Requirements
- Authelia must be accessible via Docker network (`authelia:9091`)
- The `issuer` claim in the discovery document must match the public `issuer` URL

### Why Not Documented
The MAS documentation mentions `discovery_url` but doesn't emphasize its use for internal communication or bypassing SSL issues in development.

---

## 9. PostgreSQL Data Persistence Across Deployments

### Severity
**CRITICAL** - Causes complete deployment failure

### Problem
PostgreSQL data directories persist between deployments, even after cleanup attempts. When you re-run `deploy.sh`, it generates NEW passwords in `.env`, but PostgreSQL continues using the OLD password from when the data directory was first initialized. This causes authentication failures for all services (MAS, Synapse, Authelia).

**Symptoms:**
```
Error: could not connect to the database
Caused by:
    0: error returned from database: password authentication failed for user "synapse"
```

### Root Cause
1. PostgreSQL only initializes the database on first run (when `postgres/data` is empty)
2. Once initialized, PostgreSQL ignores the `POSTGRES_PASSWORD` environment variable
3. User passwords are stored in PostgreSQL's internal authentication system
4. Even if you delete `.env` and configs, the `postgres/data` directory may survive
5. New deployment generates new passwords, but PostgreSQL still expects old passwords

### Detection
Check the timestamps:
```bash
# Check when PostgreSQL data was created
ls -la postgres/data/

# Check when current .env was generated
head -2 .env

# If postgres/data is OLDER than .env, you have a mismatch!
```

### Solution 1: Clean Slate (Recommended)
```bash
# Stop all services
docker compose down

# Delete all data directories
sudo rm -rf postgres/data synapse/data mas/data mas/certs caddy/data caddy/config

# Re-run deployment
./quickstart.sh   # or ./deploy.sh
```

### Solution 2: Manual Password Update (Preserves Data)
```bash
# Get the new password from .env
source .env

# Connect to PostgreSQL
docker compose exec postgres psql -U synapse

# Update the password
ALTER USER synapse WITH PASSWORD 'new_password_from_env';
\q

# Restart all services
docker compose restart
```

### Prevention
Both `quickstart.sh` and `deploy.sh` detect existing data directories and warn before proceeding. `quickstart.sh` explicitly wipes `postgres/data` when the user confirms, preventing the mismatch.

### Why This Happens
- Docker volumes and bind mounts persist even after `docker compose down`
- `sudo` operations (used to fix permissions) may leave directories owned by root
- Partial cleanup (e.g., deleting `.env` but not `postgres/data`) creates inconsistencies
- PostgreSQL's security model treats the initial password as authoritative

### Impact on All Deployment Variants
This issue affects:
- Local deployment (fixed with data directory check)
- Production deployment (fixed with data directory check)
- With Authelia (affected)
- Without Authelia (affected)

All deployment modes now include the pre-flight check to prevent this issue.

### Official Documentation Gap
PostgreSQL documentation explains initialization behavior, but doesn't emphasize:
- The persistence of data across container recreations
- The implications for scripted deployments that generate dynamic passwords
- The need to either preserve passwords OR ensure clean data directories

---

## 10. DNS Resolution and TLS Certificate Trust Issues

### Severity
**CRITICAL** - Prevents authentication and causes complete login failure

### Problem
Two related issues prevent proper HTTPS communication:

1. **IPv6 DNS Priority**: System DNS resolver returns IPv6 addresses for `*.example.test` domains instead of using `/etc/hosts` IPv4 (127.0.0.1) entries. This causes connections to route to external IPs instead of localhost.

2. **Missing CA Certificate Trust**: Synapse container cannot validate HTTPS connections to MAS because:
   - Caddy uses self-signed certificates (local CA)
   - Synapse doesn't have the Caddy CA certificate mounted
   - Synapse doesn't have `SSL_CERT_FILE` environment variable set
   - Synapse can't resolve domain names to reach Caddy from within Docker network

### Root Cause
**DNS Resolution Issue:**
- `/etc/hosts` only contained IPv4 (127.0.0.1) entries
- System prefers IPv6 when available
- DNS lookups for `*.example.test` return public IPv6 addresses
- Connections timeout or fail when reaching external IPs

**Certificate Trust Issue:**
- With MSC3861 enabled, Synapse must connect to MAS over HTTPS
- MAS issuer URL is `https://auth.example.test/`
- Synapse needs to fetch OIDC discovery metadata from MAS
- Without CA certificate trust, Synapse gets `SSL routines::tlsv1 alert internal error`

**Docker Network Resolution:**
- Containers use host's DNS resolver by default
- Domain names resolve to external IPs from inside containers
- Containers need `extra_hosts` to route domains back to host machine
- Host machine forwards to Caddy via published port 443

### Symptoms
- User cannot log in via Element
- Synapse logs show no auth-related errors (because issue happens during HTTPS connection)
- MAS logs show no connection attempts from Synapse
- Testing from host with `curl https://matrix.example.test/` hangs/times out
- Testing with `curl --resolve matrix.example.test:443:127.0.0.1` works fine
- Testing from Synapse container: `curl https://auth.example.test/` fails with SSL error
- `getent hosts matrix.example.test` returns IPv6 address instead of 127.0.0.1

### Detection
```bash
# Check DNS resolution (should return 127.0.0.1 or ::1, not external IP)
getent hosts matrix.example.test

# Test from host (should work)
curl -k https://matrix.example.test/_matrix/client/versions

# Test from Synapse container (should work after fix)
docker exec matrix-synapse curl -sS https://auth.example.test/.well-known/openid-configuration

# Check if CA cert is mounted
docker exec matrix-synapse ls -la /certs/

# Check SSL_CERT_FILE environment variable
docker exec matrix-synapse env | grep SSL_CERT_FILE
```

### Solution Applied

**1. Fix /etc/hosts (Host Machine)**
Added IPv6 localhost entries alongside IPv4:
```bash
# /etc/hosts
127.0.0.1  matrix.example.test element.example.test auth.example.test authelia.example.test
::1  matrix.example.test element.example.test auth.example.test authelia.example.test
```

**2. Mount Caddy CA Certificate in Synapse**
```yaml
# docker-compose.local.yml - synapse service
volumes:
  - ./synapse/data:/data
  - ./mas/certs:/certs:ro  # Mount CA certificate directory
environment:
  SYNAPSE_CONFIG_PATH: /data/homeserver.yaml
  SSL_CERT_FILE: /certs/caddy-ca.crt  # Trust Caddy's self-signed CA
```

**3. Configure Domain Resolution in Synapse**
```yaml
# docker-compose.local.yml - synapse service
extra_hosts:
  - "auth.example.test:host-gateway"
  - "matrix.example.test:host-gateway"
```

This allows Synapse to:
- Resolve `auth.example.test` to the host machine
- Connect via host's port 443 (forwarded to Caddy)
- Trust the connection using the mounted CA certificate

### Impact on All Deployment Variants
This issue affects:
- Local deployment (fixed with IPv6 hosts entries and Synapse CA config)
- Production deployment (would need same fixes - IPv6 handled by real DNS, CA certs handled by Let's Encrypt)
- With Authelia (affected - Synapse needs to reach MAS)
- Without Authelia (affected - Synapse still needs to reach MAS)

### Why This Happens
1. **Local Development Environment**: Uses self-signed certificates requiring explicit trust
2. **Docker Networking**: Containers don't automatically use host's `/etc/hosts` file
3. **MSC3861 Architecture**: Synapse MUST be able to reach MAS via HTTPS (issuer URL) to validate tokens
4. **IPv6 Priority**: Modern systems prefer IPv6 over IPv4 when both protocols are available

### Production Deployment Notes
In production with real DNS and Let's Encrypt certificates:
- IPv6 DNS resolution works correctly (points to your actual server)
- Let's Encrypt certificates are trusted by default
- `extra_hosts` not needed (real DNS works)
- `SSL_CERT_FILE` not needed (system trusts Let's Encrypt CA)

This issue is specific to local development with:
- Self-signed certificates
- `/etc/hosts`-based DNS
- Docker networking

### Official Documentation Gap
Neither Matrix/Synapse nor Caddy documentation clearly explains:
- The requirement for Synapse to trust the CA when using MSC3861
- The need to configure DNS resolution from containers to host
- The IPv6 priority behavior with `/etc/hosts`
- The TLS requirements for MSC3861 delegated authentication

---

## 11. FluffyChat Cross-Signing Setup with MAS

### Severity
**MODERATE** — Confusing UX, but workaround exists

### Problem
When logging into FluffyChat with MAS authentication, attempting to set up encryption or chat backup redirects users to:
```
https://auth.example.com/account/?action=org.matrix.cross_signing_reset
```
Users are told to "click the continue button" on this page, but **no continue button exists** — the page only shows the account overview.

### Root Cause
A gap between specification and implementation:
1. **MSC4312** (merged Nov 2025) defines the `org.matrix.cross_signing_reset` account management action
2. **MAS v1.15.0** advertises this action in its `account_management_actions_supported` capabilities
3. **FluffyChat** sees this capability and tries to use it
4. **However**, MAS does not yet have the UI implemented for handling this action

### Symptoms
- FluffyChat prompts "Reset cryptographic identity?" or "Activate chat backup"
- Clicking opens MAS account page in browser with no continue button
- Cross-signing cannot be set up through FluffyChat

### Verification
```bash
curl -s "https://auth.example.com/.well-known/openid-configuration" | jq '.account_management_actions_supported'
```
Will include `"org.matrix.cross_signing_reset"` even though the UI is not implemented.

### Solution: Set Up Cross-Signing via Element First

**Step 1 — Set up cross-signing in Element:**
1. Open Element Web (`https://element.example.com`)
2. Avatar → All Settings → Security & Privacy → Set up Secure Backup
3. Generate a Security Key and **save it somewhere safe**
4. Complete the setup

**Step 2 — Use the same key in FluffyChat:**
1. FluffyChat → Settings → Security → Chat Backup
2. Enter the security key/passphrase from Step 1

### Alternative: Reset Cross-Signing via Database

If cross-signing is in a broken state (empty secret storage):

```bash
docker compose exec postgres psql -U synapse -d synapse
```
```sql
BEGIN;
DELETE FROM e2e_cross_signing_keys WHERE user_id = '@username:example.com';
DELETE FROM e2e_cross_signing_signatures WHERE user_id = '@username:example.com';
DELETE FROM account_data WHERE user_id = '@username:example.com'
  AND account_data_type IN (
    'm.cross_signing.master',
    'm.cross_signing.self_signing',
    'm.cross_signing.user_signing',
    'm.megolm_backup.v1'
  );
COMMIT;
```

After reset, log out and back in to FluffyChat — it will prompt to set up encryption fresh.

### Future Resolution
Track at:
- [MSC4312](https://github.com/matrix-org/matrix-spec-proposals/pull/4312)
- [MAS Issue #1942](https://github.com/matrix-org/matrix-authentication-service/issues/1942)

---

## Configuration Changes Checklist

When making changes to the stack, follow this checklist to avoid common issues:

### Changing Domains
- [ ] Update Authelia cookie domain (no leading dot!)
- [ ] Update all service URLs in MAS config
- [ ] Update Authelia OIDC client redirect URIs
- [ ] Update Element Web config.json
- [ ] Update Synapse homeserver.yaml (MSC3861 issuer)
- [ ] Update Caddyfile domains
- [ ] Update /etc/hosts (local) or DNS records (production)
- [ ] Restart all services

### Changing OAuth Configuration
- [ ] Update MAS config.yaml
- [ ] Delete provider from MAS database
- [ ] Restart MAS to re-sync
- [ ] Verify provider was re-created in logs
- [ ] Test authentication flow

### Updating Claims Templates
- [ ] Ensure `fetch_userinfo: true` is set
- [ ] Use `preferred_username` not `name` for Authelia
- [ ] Delete provider from MAS database
- [ ] Restart MAS
- [ ] Test registration/login flow

### Debugging TLS Issues
- [ ] Check if MAS has Caddy CA certificate mounted
- [ ] Verify `SSL_CERT_FILE` environment variable
- [ ] Consider using `discovery_url` with HTTP for internal calls
- [ ] Check Caddy logs for SSL errors

---

---

## Common Pitfalls

### 1. Forgetting to Add Assets Resource
**Symptom:** MAS pages load but have no styling
**Fix:** Add `- name: assets` to MAS HTTP listener resources

### 2. Using `.localhost` Domain
**Symptom:** Authelia fails to start with cookie domain error
**Fix:** Use `example.test` or another non-public-suffix domain

### 3. Not Enabling Userinfo Fetching
**Symptom:** Template renders to empty string error
**Fix:** Add `fetch_userinfo: true` to MAS upstream provider

### 4. Not Restarting After Config Changes
**Symptom:** Changes don't take effect
**Fix:** Always restart the affected service: `docker compose restart service-name`

### 5. Forgetting to Delete Cached Provider
**Symptom:** MAS still uses old configuration after restart
**Fix:** Delete provider from database before restarting

### 6. Missing Redirect URIs in Authelia
**Symptom:** OAuth flow fails with invalid_request
**Fix:** Add all possible redirect URI patterns to Authelia client config

### 7. Using `{{ user.name }}` Template
**Symptom:** Template renders to empty string
**Fix:** Use `{{ user.preferred_username }}` instead for Authelia

### 8. SSL Certificate Trust Issues
**Symptom:** MAS can't fetch Authelia metadata
**Fix:** Mount Caddy CA certificate or use internal discovery_url

---

## Security Advisories

### CVE-2025-49090 — Synapse room version default

Synapse versions before 1.130.0 default to room version 10, which has a known vulnerability. This stack sets the default to room version 12 in `homeserver.yaml`:

```yaml
default_room_version: "12"
```

This is applied automatically by `deploy.sh` and `quickstart.sh`. If you have an existing `homeserver.yaml` generated before this fix, add the line manually and restart Synapse.

### Updating images

The compose file uses `latest` for all images. To apply any security update:

```bash
docker compose pull
docker compose up -d
```

---

## Additional Resources

- [Public Suffix List](https://publicsuffix.org/)
- [MAS Configuration Reference](https://element-hq.github.io/matrix-authentication-service/)
- [Authelia Configuration](https://www.authelia.com/configuration/)
- [Synapse Configuration](https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html)
