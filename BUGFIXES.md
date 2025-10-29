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
- ❌ `{{ user.name }}` - Not provided by Authelia
- ✅ `{{ user.preferred_username }}` - Works (contains username)
- ✅ `{{ user.email }}` - Works

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

## Testing Checklist

After deployment, verify each component:

### 1. Basic Connectivity
```bash
# Test all HTTPS endpoints
curl -I https://matrix.example.test
curl -I https://element.example.test
curl -I https://auth.example.test
curl -I https://authelia.example.test

# All should return HTTP 200 or appropriate redirect
```

### 2. OIDC Discovery
```bash
curl https://auth.example.test/.well-known/openid-configuration | jq
# Should return valid OIDC discovery document
```

### 3. MAS Assets
```bash
curl -I https://auth.example.test/assets/shared-CVCHz34K.css
# Should return HTTP 200
```

### 4. Matrix Well-Known
```bash
curl https://matrix.example.test/.well-known/matrix/client | jq
# Should return homeserver and authentication issuer
```

### 5. Full Authentication Flow
1. Navigate to Element: `https://element.example.test`
2. Click "Sign In"
3. Verify redirect to MAS: `https://auth.example.test`
4. Verify redirect to Authelia: `https://authelia.example.test`
5. Log in with credentials
6. Complete 2FA setup
7. Verify redirect back to Element
8. Verify successful login

### 6. Database Verification
```bash
# Check MAS provider configuration
docker compose exec postgres psql -U synapse -d mas -c \
  "SELECT upstream_oauth_provider_id, fetch_userinfo, claims_imports FROM upstream_oauth_providers;"

# Verify fetch_userinfo is 't' (true)
# Verify claims_imports uses preferred_username
```

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

## Version-Specific Notes

### MAS v1.5.0
- Confirmed working with all fixes applied
- Assets must be explicitly enabled in listener resources
- `fetch_userinfo` defaults to `false`

### Authelia v4.39.13
- Rejects public suffix list domains for cookies
- Provides `preferred_username` claim, not `name`
- Requires exact redirect URI matches
- `jwt_secret` is deprecated, use `identity_validation.reset_password.jwt_secret`

### Synapse (latest)
- MSC3861 (OAuth delegation) is marked as experimental
- Works reliably with MAS when properly configured

---

## Additional Resources

- [Public Suffix List](https://publicsuffix.org/)
- [OIDC Core Specification](https://openid.net/specs/openid-connect-core-1_0.html)
- [MAS Configuration Reference](https://element-hq.github.io/matrix-authentication-service/)
- [Authelia Configuration](https://www.authelia.com/configuration/)

---

## Contributing to This Document

If you encounter additional issues not covered here:
1. Document the problem clearly
2. Include error messages
3. Explain the root cause
4. Provide the solution
5. Note why it's not in official docs
6. Add to the appropriate section

This helps future deployments avoid the same pitfalls!
