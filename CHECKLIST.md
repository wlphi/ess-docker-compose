# Setup Checklist

Use this checklist to track your setup progress.

## Initial Setup

- [ ] Edit `.env` file with secure passwords and secrets
- [ ] Generate secrets: `openssl rand -base64 32` (do this 4 times for different secrets)
- [ ] Set your domain name in `.env` (or keep `matrix.localhost` for local testing)

## Synapse Setup

- [ ] Run `./setup-synapse.sh` to generate Synapse config
- [ ] Edit `./synapse/data/homeserver.yaml`:
  - [ ] Configure PostgreSQL database connection
  - [ ] Set `enable_registration` as desired
  - [ ] Add MAS experimental features (msc3861)
  - [ ] Set `server_name` to your domain

## Authelia Setup

- [ ] Generate password hash: `docker run authelia/authelia:latest authelia crypto hash generate argon2 --password 'yourpassword'`
- [ ] Update `./authelia/config/users_database.yml` with password hash
- [ ] Generate RSA key: `openssl genrsa -out authelia_private.pem 4096`
- [ ] Copy RSA key to `./authelia/config/configuration.yml`
- [ ] Generate client secret: `docker run authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72 --random.charset rfc3986`
- [ ] Update client secret in both Authelia and MAS configs

## MAS Setup

- [ ] Generate MAS signing key: `openssl genrsa 4096 | openssl pkcs8 -topk8 -nocrypt > mas-signing.key`
- [ ] Copy signing key to `./mas/config/config.yaml`
- [ ] Update database password in `./mas/config/config.yaml`
- [ ] Update client secret to match Authelia

## Start Services

- [ ] Start PostgreSQL: `docker compose up -d postgres`
- [ ] Wait for PostgreSQL to be ready (check logs)
- [ ] Start all services: `docker compose up -d`
- [ ] Check all services are running: `docker compose ps`
- [ ] Check logs for errors: `docker compose logs`

## Test Basic Functionality

- [ ] Access Element Web at http://localhost:8080
- [ ] Try to sign in (should redirect through MAS → Authelia)
- [ ] Complete 2FA setup in Authelia
- [ ] Successfully log into Element
- [ ] Create a room
- [ ] Send a test message

## Bridge Setup (Optional)

- [ ] Run `./setup-bridges.sh` to generate bridge configs
- [ ] Edit each bridge config at `./bridges/{bridge}/config/config.yaml`
- [ ] Copy registration files to synapse data directory
- [ ] Add registration files to `homeserver.yaml`
- [ ] Restart Synapse: `docker compose restart synapse`

### Test Bridges

- [ ] **Telegram**: Start chat with `@telegrambot:matrix.localhost`, send `login`
- [ ] **WhatsApp**: Start chat with `@whatsappbot:matrix.localhost`, send `login`
- [ ] **Signal**: Start chat with `@signalbot:matrix.localhost`, send `link`

## Production Readiness (When Moving to Production)

- [ ] Set up reverse proxy (Caddy/nginx) with HTTPS
- [ ] Configure real domain names
- [ ] Update all URLs to use HTTPS and real domains
- [ ] Set up email server for Authelia notifications
- [ ] Configure firewall rules
- [ ] Set up automated backups
- [ ] Review security settings in all configs
- [ ] Test from external network
- [ ] Set up monitoring/alerting
- [ ] Document your specific configuration

## Notes

Write any issues or notes here:

```
[Your notes]
```
